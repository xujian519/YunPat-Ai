import Foundation

/// 会话来源标记 — 每条会话的可审计来源
public enum SessionSource: String, Sendable, Codable {
    case chat
    case plugin
    case http
    case schedule
    case watcher
    case patentDraft
    case patentOA
    case patentSearch
    case patentAnalysis
}

/// 会话元数据
public struct ChatSessionData: Sendable, Codable {
    public let id: UUID
    public let source: SessionSource
    public let sourcePluginId: String?
    public let externalSessionKey: String?
    public let dispatchTaskId: UUID?
    public let caseId: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        source: SessionSource = .chat,
        sourcePluginId: String? = nil,
        externalSessionKey: String? = nil,
        dispatchTaskId: UUID? = nil,
        caseId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.sourcePluginId = sourcePluginId
        self.externalSessionKey = externalSessionKey
        self.dispatchTaskId = dispatchTaskId
        self.caseId = caseId
        self.createdAt = createdAt
    }
}

/// LoopResult 拓展：关联会话来源
extension LoopResult {
    public var source: SessionSource? {
        // LoopResult 本身不含来源信息 — 由 surface 在创建时标记
        nil
    }
}
