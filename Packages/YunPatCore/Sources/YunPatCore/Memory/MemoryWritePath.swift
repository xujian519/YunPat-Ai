import Foundation

/// 异步写路径：bufferTurn（单次 SQL insert / JSON append）→ 防抖 → flush（单次 LLM 蒸馏）
///
/// 热路径（每轮对话）：只做一次轻量存储 + 防抖 arm，无 LLM。
/// 蒸馏：session 结束后（60s 防抖或 session 切换），一次 LLM 调用处理整 session。
///
/// 持久化：pendingSignals 完整序列化到 ~/.yunpat/memory/pending_signals.json，
/// 崩溃恢复时可完整恢复信号队列而非哑信号。
public actor MemoryWritePath {
    public static let shared: MemoryWritePath = MemoryWritePath()
    private let store: MemoryStore
    private var pendingSignals: [PendingSignal] = []
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    private var retryCount: Int = 0

    private static let persistenceURL: URL = {
        let home: URL = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".yunpat/memory")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pending_signals.json")
    }()

    /// 蒸馏回调（由外部注入 LLM 调用）
    public var distillHandler: (@Sendable ([PendingSignal]) async -> DistillResult?)?

    public init(
        store: MemoryStore = MemoryStore(),
        debounceInterval: TimeInterval = 60,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 5
    ) {
        self.store = store
        self.debounceInterval = debounceInterval
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }

    // MARK: - Public API

    /// 热路径：记录一次对话轮次（仅轻量存储 + 防抖）
    public func bufferTurn(user: String, assistant: String, caseId: String) async {
        let signal: PendingSignal = PendingSignal(
            id: UUID(),
            user: user, assistant: assistant,
            caseId: caseId, timestamp: Date()
        )
        pendingSignals.append(signal)
        persistPendingSignals()

        // 刷新防抖
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            if !Task.isCancelled {
                await self.flush(caseId: caseId)
            }
        }
    }

    /// 强制立即 flush（session 切换 / 用户手动保存时调用）
    public func flush(caseId: String) async {
        guard !pendingSignals.isEmpty else { return }
        debounceTask?.cancel()
        debounceTask = nil

        let signals: [PendingSignal] = pendingSignals
        pendingSignals.removeAll()
        clearPersistedSignals()

        // 检查 novelty（最少 80 字才有蒸馏价值）
        let totalChars: Int = signals.map { $0.user.count + $0.assistant.count }.reduce(0, +)
        guard totalChars >= 80 else { return }

        // 有 distill handler 则调用 LLM 蒸馏
        if let handler = distillHandler {
            if let result = await handler(signals) {
                if !result.episode.summary.isEmpty {
                    var context = await store.loadCaseContext(caseId) ?? CaseContext(caseId: caseId)
                    context.inventionPoints.append(contentsOf: result.facts)
                    context.lastModified = Date()
                    do {
                        try await store.saveCaseContext(context)
                    } catch {
                        print("[MemoryWritePath] Failed to save case context for \(caseId): \(error)")
                    }
                }
                retryCount = 0
            } else {
                // 蒸馏失败 → bounded retry
                if retryCount < maxRetries {
                    retryCount += 1
                    pendingSignals.append(contentsOf: signals)
                    persistPendingSignals()
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                    await flush(caseId: caseId)
                } else {
                    print(
                        "[MemoryWritePath] Distillation failed after"
                            + " \(maxRetries) retries, dropping \(signals.count) signals"
                    )
                    retryCount = 0
                }
            }
        }
    }

    // MARK: - Recovery

    /// 启动时从 JSON 文件恢复未处理的信号
    public func recoverOrphanedSignals() async {
        guard let data = try? Data(contentsOf: Self.persistenceURL),
              let decoded = try? JSONDecoder().decode([PendingSignal].self, from: data),
              !decoded.isEmpty else { return }
        pendingSignals.append(contentsOf: decoded)
        persistPendingSignals()
        if let caseId = decoded.last?.caseId {
            debounceTask?.cancel()
            debounceTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
                if !Task.isCancelled {
                    await self.flush(caseId: caseId)
                }
            }
        }
    }

    /// 获取待处理信号数
    public var pendingCount: Int { pendingSignals.count }

    // MARK: - Persistence

    private func persistPendingSignals() {
        guard let data = try? JSONEncoder().encode(pendingSignals) else { return }
        try? data.write(to: Self.persistenceURL, options: .atomic)
    }

    private func clearPersistedSignals() {
        let empty: [PendingSignal] = []
        guard let data = try? JSONEncoder().encode(empty) else { return }
        try? data.write(to: Self.persistenceURL, options: .atomic)
    }
}

// MARK: - Types

/// 待处理信号 — 缓冲一次对话轮次的输入输出
public struct PendingSignal: Sendable, Codable {
    public let id: UUID
    public let user: String
    public let assistant: String
    public let caseId: String
    public let timestamp: Date
    public init(id: UUID, user: String, assistant: String, caseId: String, timestamp: Date) {
        self.id = id
        self.user = user
        self.assistant = assistant
        self.caseId = caseId
        self.timestamp = timestamp
    }
}

/// 蒸馏结果 — 包含事件摘要和提取的事实列表
public struct DistillResult: Sendable {
    public let episode: EpisodeDigest
    public let facts: [String]
    public init(episode: EpisodeDigest, facts: [String]) {
        self.episode = episode
        self.facts = facts
    }
}

/// 事件摘要 — 包含摘要、话题、实体和决策要点
public struct EpisodeDigest: Sendable {
    public let summary: String
    public let topics: [String]
    public let entities: [String]
    public let decisions: [String]
    public init(summary: String, topics: [String] = [], entities: [String] = [], decisions: [String] = []) {
        self.summary = summary
        self.topics = topics
        self.entities = entities
        self.decisions = decisions
    }
}
