import Foundation

/// 代理执行流程模式 — 控制用户干预程度（copilot / guided / fullAgent）
public enum AgentFlow: Sendable {
    case copilot
    case guided
    case fullAgent
}

/// 计划模式 — 控制专利流程中的交互策略（auto / interactive / readOnly）
public enum PlanMode: Sendable {
    case auto
    case interactive
    case readOnly
}

/// 循环引擎状态 — idle / running / waitingApproval / error / conflictPause
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

/// 审批请求 — 等待用户确认的上下文，包含摘要、详细说明和选项列表
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

/// 冲突解决请求 — AI 与用户同时编辑同一文档时暂停并提示用户
public struct ConflictResolutionRequest: Sendable {
    public let document: String
    public let message: String
    public init(document: String, message: String = "AI 正在写入此文档，是否暂停 AI 先让你编辑？") {
        self.document = document
        self.message = message
    }
}

/// 循环配置 — 最大修订次数等基础参数
public struct LoopConfig: Sendable {
    public let maxRevisionCycles: Int
    public init(maxRevisionCycles: Int = 3) { self.maxRevisionCycles = maxRevisionCycles }
}

/// 循环执行结果 — completed / needsClarification / cancelled 等终结状态
public enum LoopResult: Sendable {
    case completed(String)
    case needsClarification([String])
    case cancelled
    case needsRevision([Issue])
    case exceededRevisionLimit([Issue])
}

/// 问题描述 — 含警告/错误的描述信息及严重级别
public struct Issue: Sendable {
    public let severity: IssueSeverity
    public let description: String
    public init(severity: IssueSeverity = .error, description: String) {
        self.severity = severity
        self.description = description
    }
}

/// 问题严重级别 — warning 或 error
public enum IssueSeverity: Sendable {
    case warning
    case error
}

/// 执行计划 — 由策略描述和步骤列表组成
public struct ExecutionPlan: Sendable {
    public let strategy: String
    public let steps: [PlanStep]
    public init(strategy: String = "", steps: [PlanStep] = []) {
        self.strategy = strategy
        self.steps = steps
    }
}

/// 计划步骤 — 执行计划中的一个步骤，含名称、描述和绑定规则
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

/// 步骤执行结果 — 单步的名称、输出和成功状态
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

/// 执行结果 — 包含步骤结果列表和产物路径列表
public struct ExecutionResult: Sendable {
    public let stepResults: [StepResult]
    public let artifacts: [String]
    public init(stepResults: [StepResult] = [], artifacts: [String] = []) {
        self.stepResults = stepResults
        self.artifacts = artifacts
    }
}

/// 审查结果 — 包含裁定、问题列表、证据和 PatentRubric 评分
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
