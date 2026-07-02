import Foundation

public struct CheckResult: Sendable {
    public let constraintId: String
    public let passed: Bool
    public let severity: CheckSeverity
    public let message: String
    public let suggestion: String?

    public init(
        constraintId: String,
        passed: Bool,
        severity: CheckSeverity,
        message: String,
        suggestion: String? = nil
    ) {
        self.constraintId = constraintId
        self.passed = passed
        self.severity = severity
        self.message = message
        self.suggestion = suggestion
    }
}

public enum CheckSeverity: String, Sendable {
    case error
    case warning
    case info
}

public actor ChecklistEngine {

    private static let constraintMap: [String: [RuleConstraint]] = [
        "drafting": [
            RuleConstraint(
                articleId: "A22.2",
                articleName: "新颖性",
                requirement: .must,
                description: "权利要求应具备新颖性",
                applicableStages: ["撰写权利要求", "全面检查"]
            ),
            RuleConstraint(
                articleId: "A22.3",
                articleName: "创造性",
                requirement: .must,
                description: "权利要求应具备创造性",
                applicableStages: ["撰写权利要求", "全面检查"]
            ),
            RuleConstraint(
                articleId: "A26.3",
                articleName: "充分公开",
                requirement: .must,
                description: "说明书应充分公开发明",
                applicableStages: ["撰写说明书", "全面检查"]
            ),
            RuleConstraint(
                articleId: "A26.4",
                articleName: "清楚支持",
                requirement: .must,
                description: "权利要求应清楚并得到说明书支持",
                applicableStages: ["撰写权利要求", "全面检查"]
            ),
            RuleConstraint(
                articleId: "A25",
                articleName: "授权客体",
                requirement: .must,
                description: "不属于不授权主题",
                applicableStages: ["全面检查"]
            ),
            RuleConstraint(
                articleId: "A33",
                articleName: "修改超范围",
                requirement: .note,
                description: "修改不应超出原始范围",
                applicableStages: ["全面检查"]
            )
        ],
        "invalidation": [
            RuleConstraint(
                articleId: "A22.2",
                articleName: "新颖性",
                requirement: .must,
                description: "目标专利不具备新颖性",
                applicableStages: ["分析"]
            ),
            RuleConstraint(
                articleId: "A22.3",
                articleName: "创造性",
                requirement: .must,
                description: "目标专利不具备创造性",
                applicableStages: ["分析"]
            )
        ],
        "infringement": [
            RuleConstraint(
                articleId: "A67",
                articleName: "全面覆盖原则",
                requirement: .must,
                description: "被控产品覆盖全部技术特征",
                applicableStages: ["特征对比"]
            )
        ]
    ]

    public func loadConstraints(for caseType: String) -> [RuleConstraint] {
        Self.constraintMap[caseType] ?? []
    }

    public func summary(_ results: [CheckResult]) -> String {
        let p = results.filter(\.passed).count
        let f = results.filter { !$0.passed }.count
        return "通过: \(p), 未通过: \(f)"
    }
}
