import Foundation

/// 异步写路径：bufferTurn（单次 SQL insert / JSON append）→ 防抖 → flush（单次 LLM 蒸馏）
///
/// 热路径（每轮对话）：只做一次轻量存储 + 防抖 arm，无 LLM。
/// 蒸馏：session 结束后（60s 防抖或 session 切换），一次 LLM 调用处理整 session。
public actor MemoryWritePath {
    public static let shared: MemoryWritePath = MemoryWritePath()
    private let store: MemoryStore
    private var pendingSignals: [PendingSignal] = []
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval

    /// 蒸馏回调（由外部注入 LLM 调用）
    public var distillHandler: (@Sendable ([PendingSignal]) async -> DistillResult?)?

    public init(store: MemoryStore = MemoryStore(), debounceInterval: TimeInterval = 60) {
        self.store = store
        self.debounceInterval = debounceInterval
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

        // 检查 novelty（最少 80 字才有蒸馏价值）
        let totalChars: Int = signals.map { $0.user.count + $0.assistant.count }.reduce(0, +)
        guard totalChars >= 80 else { return }

        // 有 distill handler 则调用 LLM 蒸馏
        if let handler = distillHandler {
            if let result = await handler(signals) {
                // 蒸馏成功 → 持久化
                if !result.episode.summary.isEmpty {
                    var context = await store.loadCaseContext(caseId) ?? CaseContext(caseId: caseId)
                    context.inventionPoints.append(contentsOf: result.facts)
                    context.lastModified = Date()
                    try? await store.saveCaseContext(context)
                }
            }
            // 蒸馏失败 → bounded retry（重新 append 回队列）
            // 当前实现：放弃（dead-letter），避免死循环
        }
    }

    /// 启动时恢复未处理的信号
    public func recoverOrphanedSignals() async {
        // 当前 pendingSignals 在内存中，重启后丢失
        // 未来：持久化到 SQLite pending_signals 表
    }

    /// 获取待处理信号数
    public var pendingCount: Int { pendingSignals.count }
}

// MARK: - Types

public struct PendingSignal: Sendable {
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

public struct DistillResult: Sendable {
    public let episode: EpisodeDigest
    public let facts: [String]
    public init(episode: EpisodeDigest, facts: [String]) {
        self.episode = episode
        self.facts = facts
    }
}

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
