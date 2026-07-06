import Foundation
import YunPatNetworking

/// 工具调用审计记录器 — 记录每次工具调用的详细信息
///
/// 记录内容：
/// - 工具名称、输入摘要、时间戳、执行耗时
/// - 结果摘要、是否错误
/// - 权限决策（allow/block）
/// - 关联会话 ID
///
/// 存储方式：内存环形缓冲区（最近 maxEntries 条）+ JSON 文件持久化
public actor ToolAuditRecorder {

    /// 单条审计记录
    public struct AuditEntry: Sendable, Identifiable, Codable, Hashable {
        public let id: UUID
        public let toolName: String
        public let timestamp: Date
        public let duration: TimeInterval
        public let inputSummary: String
        public let resultSummary: String
        public let isError: Bool
        public let permissionDecision: String
        public let sessionId: String?

        public init(
            id: UUID = UUID(),
            toolName: String,
            timestamp: Date = Date(),
            duration: TimeInterval,
            inputSummary: String,
            resultSummary: String,
            isError: Bool,
            permissionDecision: String = "allow",
            sessionId: String? = nil
        ) {
            self.id = id
            self.toolName = toolName
            self.timestamp = timestamp
            self.duration = duration
            self.inputSummary = inputSummary
            self.resultSummary = resultSummary
            self.isError = isError
            self.permissionDecision = permissionDecision
            self.sessionId = sessionId
        }
    }

    /// 审计统计摘要
    public struct AuditSummary: Sendable {
        public let totalCalls: Int
        public let totalErrors: Int
        public let toolCallCounts: [String: Int]
        public let mostCalled: String?
        public let errorRate: Double

        fileprivate init(entries: [AuditEntry]) {
            totalCalls = entries.count
            totalErrors = entries.filter { $0.isError }.count
            var counts: [String: Int] = [:]
            for entry in entries {
                counts[entry.toolName, default: 0] += 1
            }
            toolCallCounts = counts
            mostCalled = counts.max(by: { $0.value < $1.value })?.key
            errorRate = totalCalls > 0 ? Double(totalErrors) / Double(totalCalls) : 0
        }
    }

    public static let shared: ToolAuditRecorder = ToolAuditRecorder()

    private var entries: [AuditEntry] = []
    private let maxEntries: Int
    private let persistenceURL: URL?

    private init(maxEntries: Int = 1000) {
        self.maxEntries = maxEntries
        let paths: [String] = NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory, .userDomainMask, true
        )
        var url: URL?
        if let base: String = paths.first {
            let dir: String = "\(base)/YunPatCore/Audit"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            url = URL(fileURLWithPath: "\(dir)/tool_audit.json")
        }
        self.persistenceURL = url
        self.entries = Self.loadPersisted(url: url)
    }

    // MARK: - Public API

    /// 记录一条审计条目
    public func record(_ entry: AuditEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        persist()
    }

    /// 便捷方法：记录工具调用
    public func recordToolCall(
        toolName: String,
        duration: TimeInterval,
        inputSummary: String,
        resultSummary: String,
        isError: Bool,
        permissionDecision: String = "allow",
        sessionId: String? = nil
    ) {
        let entry: AuditEntry = AuditEntry(
            toolName: toolName,
            duration: duration,
            inputSummary: inputSummary,
            resultSummary: resultSummary,
            isError: isError,
            permissionDecision: permissionDecision,
            sessionId: sessionId
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        persist()
    }

    /// 获取最近 N 条记录
    public func recent(limit: Int = 50) -> [AuditEntry] {
        Array(entries.suffix(limit))
    }

    /// 按工具名搜索审计记录
    public func search(toolName: String?, limit: Int = 50) -> [AuditEntry] {
        guard let name: String = toolName, !name.isEmpty else {
            return recent(limit: limit)
        }
        return entries
            .filter { $0.toolName.localizedCaseInsensitiveContains(name) }
            .suffix(limit)
    }

    /// 获取审计统计摘要
    public func summary() -> AuditSummary {
        AuditSummary(entries: entries)
    }

    /// 清除所有记录
    public func clear() {
        entries.removeAll()
        persist()
    }

    /// 导出为 JSON 数据
    public func export() -> Data? {
        try? JSONEncoder().encode(entries)
    }

    // MARK: - Persistence

    private func persist() {
        guard let url: URL = persistenceURL else { return }
        guard let data: Data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func loadPersisted(url: URL?) -> [AuditEntry] {
        guard let url: URL = url,
              let data: Data = try? Data(contentsOf: url),
              let loaded: [AuditEntry] = try? JSONDecoder().decode([AuditEntry].self, from: data)
        else { return [] }
        return loaded
    }
}
