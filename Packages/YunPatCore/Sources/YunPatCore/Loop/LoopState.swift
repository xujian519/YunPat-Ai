import Foundation

public enum AgentFlow: Sendable {
    case copilot
    case guided
    case fullAgent
}

public enum PlanMode: Sendable {
    case auto
    case interactive
    case readOnly
}

public enum LoopState: Sendable {
    case idle
    case running(step: String)
    case waitingApproval(ApprovalRequest)
    case error(Error)
    case conflictPause(ConflictResolutionRequest)
}

public struct ApprovalRequest: Sendable {
    public let id: UUID
    public let summary: String
    public let detail: String
    public let options: [String]
    public init(id: UUID = UUID(), summary: String, detail: String, options: [String] = ["确认", "取消"]) {
        self.id = id; self.summary = summary; self.detail = detail; self.options = options
    }
}

public struct ConflictResolutionRequest: Sendable {
    public let document: String
    public let message: String
    public init(document: String, message: String = "AI 正在写入此文档，是否暂停 AI 先让你编辑？") {
        self.document = document; self.message = message
    }
}

public struct LoopConfig: Sendable {
    public let maxRevisionCycles: Int
    public init(maxRevisionCycles: Int = 3) { self.maxRevisionCycles = maxRevisionCycles }
}

public enum LoopResult: Sendable {
    case completed(String)
    case needsClarification([String])
    case cancelled
    case needsRevision([Issue])
    case exceededRevisionLimit([Issue])
}

public struct Issue: Sendable {
    public let severity: IssueSeverity
    public let description: String
    public init(severity: IssueSeverity = .error, description: String) {
        self.severity = severity; self.description = description
    }
}

public enum IssueSeverity: Sendable {
    case warning
    case error
}
