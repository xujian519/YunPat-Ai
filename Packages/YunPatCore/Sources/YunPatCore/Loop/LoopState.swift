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

    public var description: String {
        switch self {
        case .idle: return "空闲"
        case .running(let step): return "运行中: \(step)"
        case .waitingApproval: return "等待确认"
        case .error: return "错误"
        case .conflictPause: return "冲突暂停"
        }
    }
}

public struct ApprovalRequest: Sendable {
    public let id: UUID
    public let summary: String
    public let detail: String
    public let options: [String]
    public init(id: UUID = UUID(), summary: String, detail: String, options: [String] = ["确认", "取消"]) {
        self.id = id
        self.summary = summary
        self.detail = detail
        self.options = options
    }
}

public struct ConflictResolutionRequest: Sendable {
    public let document: String
    public let message: String
    public init(document: String, message: String = "AI 正在写入此文档，是否暂停 AI 先让你编辑？") {
        self.document = document
        self.message = message
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
        self.severity = severity
        self.description = description
    }
}

public enum IssueSeverity: Sendable {
    case warning
    case error
}

public struct ExecutionPlan: Sendable {
    public let strategy: String
    public let steps: [PlanStep]
    public init(strategy: String = "", steps: [PlanStep] = []) {
        self.strategy = strategy
        self.steps = steps
    }
}

public struct PlanStep: Sendable {
    public let name: String
    public let description: String
    public let boundRule: String?
    public init(name: String, description: String, boundRule: String? = nil) {
        self.name = name
        self.description = description
        self.boundRule = boundRule
    }
}

public struct StepResult: Sendable {
    public let stepName: String
    public let output: String
    public let success: Bool
    public init(stepName: String, output: String, success: Bool = true) {
        self.stepName = stepName
        self.output = output
        self.success = success
    }
}

public struct ExecutionResult: Sendable {
    public let stepResults: [StepResult]
    public let artifacts: [String]
    public init(stepResults: [StepResult] = [], artifacts: [String] = []) {
        self.stepResults = stepResults
        self.artifacts = artifacts
    }
}

public struct ReviewResult: Sendable {
    public let verdict: Bool
    public let issues: [Issue]
    public let evidence: [String]
    public let rubric: PatentRubric?
    public let rubricVerdict: RubricVerdict?
    public init(
        verdict: Bool = true, issues: [Issue] = [], evidence: [String] = [], rubric: PatentRubric? = nil,
        rubricVerdict: RubricVerdict? = nil
    ) {
        self.verdict = verdict
        self.issues = issues
        self.evidence = evidence
        self.rubric = rubric
        self.rubricVerdict = rubricVerdict
    }

    /// 生成面向用户的审查报告
    public var report: String {
        var lines: [String] = []
        if let rubric = rubric {
            lines.append(rubric.report())
            lines.append("")
        }
        if !issues.isEmpty {
            lines.append("## 发现问题")
            for issue in issues {
                let icon: String = issue.severity == .error ? "❌" : "⚠️"
                lines.append("- \(icon) \(issue.description)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
