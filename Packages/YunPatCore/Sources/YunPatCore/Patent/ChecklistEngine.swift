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
        let passedCount = results.filter(\.passed).count
        let failedCount = results.filter { !$0.passed }.count
        return "通过: \(passedCount), 未通过: \(failedCount)"
    }

    public func execute(caseType: String, content: String) -> [CheckResult] {
        let constraints: [RuleConstraint] = Self.constraintMap[caseType] ?? []
        return constraints.map { constraint in
            checkConstraint(constraint, content: content)
        }
    }

    public func runChecks(caseType: String, content: String, stage: String? = nil) -> [CheckResult] {
        let constraints: [RuleConstraint] = Self.constraintMap[caseType] ?? []
        let filtered: [RuleConstraint]
        if let stage {
            filtered = constraints.filter { $0.applicableStages.contains(stage) }
        } else {
            filtered = constraints
        }
        return filtered.map { checkConstraint($0, content: content) }
    }

    private func checkConstraint(_ constraint: RuleConstraint, content: String) -> CheckResult {
        switch constraint.articleId {
        case "A26.4":
            return checkClaritySupport(constraint, content: content)
        case "A25":
            return checkSubjectMatter(constraint, content: content)
        case "A33":
            return checkAmendmentScope(constraint, content: content)
        case "A22.2", "A22.3", "A26.3", "A67":
            return CheckResult(
                constraintId: constraint.articleId,
                passed: true,
                severity: .info,
                message: "\(constraint.articleName): 需结合外部检索/对比文件确认",
                suggestion: "建议通过专利检索引擎执行 \(constraint.articleName) 深度分析"
            )
        default:
            return CheckResult(
                constraintId: constraint.articleId,
                passed: true,
                severity: .info,
                message: "\(constraint.articleName): 自动检查不可用，需人工确认"
            )
        }
    }

    private static let vagueTerms: [String] = [
        "大约", "大概", "左右", "优选地", "最好是", "可能是", "大致", "近似",
        "基本上", "例如", "等等", "约", "或多或少"
    ]

    private func checkClaritySupport(_ constraint: RuleConstraint, content: String) -> CheckResult {
        let found = Self.vagueTerms.filter { content.localizedCaseInsensitiveContains($0) }
        if found.isEmpty {
            return CheckResult(
                constraintId: constraint.articleId,
                passed: true,
                severity: .info,
                message: "清楚性检查：未检测到模糊用语",
                suggestion: nil
            )
        }
        let severity: CheckSeverity = constraint.requirement == .must ? .error : .warning
        return CheckResult(
            constraintId: constraint.articleId,
            passed: false,
            severity: severity,
            message: "清楚性检查：检测到模糊用语 \(found.joined(separator: "、"))",
            suggestion: "权利要求应避免使用模糊表述，建议使用具体数值范围或明确限定"
        )
    }

    private static let excludedSubjects: [String] = [
        "智力活动", "商业方法", "疾病的诊断", "疾病的治疗", "科学发现",
        "原子核变换", "品种", "植物品种"
    ]

    private func checkSubjectMatter(_ constraint: RuleConstraint, content: String) -> CheckResult {
        let found = Self.excludedSubjects.filter { content.localizedCaseInsensitiveContains($0) }
        if found.isEmpty {
            return CheckResult(
                constraintId: constraint.articleId,
                passed: true,
                severity: .info,
                message: "授权客体检查：未检测到排除主题",
                suggestion: nil
            )
        }
        return CheckResult(
            constraintId: constraint.articleId,
            passed: false,
            severity: .error,
            message: "授权客体检查：检测到可能的不授权主题 \(found.joined(separator: "、"))",
            suggestion: "请确认权利要求不属于专利法第25条排除的客体"
        )
    }

    private func checkAmendmentScope(_ constraint: RuleConstraint, content: String) -> CheckResult {
        let markers: [String] = ["新增", "修改为", "删除", "替换为"]
        let hasModification = markers.contains { content.localizedCaseInsensitiveContains($0) }
        let severity: CheckSeverity = hasModification ? .warning : .info
        return CheckResult(
            constraintId: constraint.articleId,
            passed: true,
            severity: severity,
            message: "修改超范围检查：\(hasModification ? "检测到修改操作，需确认不超范围" : "未检测到修改操作")",
            suggestion: hasModification ? "所有修改应可直接从原始申请文件中导出" : nil
        )
    }

    public func runFullCheck(caseType: String, content: String) -> (results: [CheckResult], summary: String) {
        let results = execute(caseType: caseType, content: content)
        return (results, summary(results))
    }
}
