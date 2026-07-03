import Foundation

public protocol ReasoningStrategy: Sendable {
    var name: String { get }
    func execute(context: ReasoningContext) async throws -> ReasoningOutput
}

public struct ReasoningContext: Sendable {
    public let userRequest: UserRequest
    public let blackboard: FactBlackboard
    public let rules: ApplicableRules

    public init(userRequest: UserRequest, blackboard: FactBlackboard, rules: ApplicableRules) {
        self.userRequest = userRequest
        self.blackboard = blackboard
        self.rules = rules
    }
}

public struct ReasoningOutput: Sendable {
    public let result: String
    public let metadata: [String: String]

    public init(result: String, metadata: [String: String] = [:]) {
        self.result = result
        self.metadata = metadata
    }
}

// MARK: - ReAct Strategy

/// ReAct (Reasoning + Acting) 策略 — 交替进行推理和行动
///
/// 流程：分析事实 → 提取关键问题 → 检索适用规则 → 生成行动建议 → 观察与总结
public struct ReactStrategy: ReasoningStrategy {
    public let name: String = "react"

    public init() {}

    public func execute(context: ReasoningContext) async throws -> ReasoningOutput {
        let facts: StructuredFacts = await context.blackboard.toStructuredFacts()
        var steps: [String] = []

        // Step 1: Thought — 分析技术领域和发明点
        let fieldSummary: String = facts.technicalField.isEmpty
            ? "未确定技术领域" : facts.technicalField
        let inventionSummary: String = facts.inventionPoints.isEmpty
            ? "未提取发明点" : facts.inventionPoints.enumerated()
                .map { "  \($0.offset + 1)) \($0.element)" }
                .joined(separator: "\n")
        steps.append("[Thought] 技术领域: \(fieldSummary)")
        steps.append("[Thought] 发明点:\n\(inventionSummary)")

        // Step 2: Action — 检索适用规则
        let ruleCount: Int = context.rules.candidates.count
        let topRules: String = context.rules.candidates.prefix(3)
            .map { "  - \($0.title) (score: \(String(format: "%.2f", $0.score)))" }
            .joined(separator: "\n")
        steps.append("[Action] 检索到 \(ruleCount) 条适用规则:\n\(topRules)")

        // Step 3: Observation — 分析约束和缺失信息
        let constraints: [RuleConstraint] = await context.blackboard.ruleConstraints
        let mustConstraints: [RuleConstraint] = constraints.filter { $0.requirement == .must }
        if !mustConstraints.isEmpty {
            let constraintList: String = mustConstraints.prefix(5)
                .map { "  - [\($0.articleId)] \($0.description)" }
                .joined(separator: "\n")
            steps.append("[Observation] 强制约束 (\(mustConstraints.count) 条):\n\(constraintList)")
        }

        let missingInfo: [String] = await context.blackboard.missingInfo
        if !missingInfo.isEmpty {
            let missingList: String = missingInfo
                .map { "  - \($0)" }
                .joined(separator: "\n")
            steps.append("[Observation] 缺失信息:\n\(missingList)")
        }

        // Step 4: Conclusion
        let problemSummary: String = facts.problem.isEmpty
            ? "待确定" : facts.problem
        let conclusion: String = """
        [Conclusion] 核心问题: \(problemSummary)
        建议行动: 基于上述规则和约束进行下一步分析
        """
        steps.append(conclusion)

        let output: String = steps.joined(separator: "\n\n")
        return ReasoningOutput(
            result: output,
            metadata: [
                "strategy": "react",
                "facts_count": "\(facts.inventionPoints.count)",
                "rules_count": "\(ruleCount)",
                "constraints_count": "\(constraints.count)"
            ]
        )
    }
}

// MARK: - Six-Step Strategy

/// 六步结构化推理 — 专利分析标准流程
///
/// 1. 理解发明 2. 确定问题 3. 检索对比 4. 分析特征 5. 综合评估 6. 得出结论
public struct SixStepStrategy: ReasoningStrategy {
    public let name: String = "six_step"

    public init() {}

    public func execute(context: ReasoningContext) async throws -> ReasoningOutput {
        let facts: StructuredFacts = await context.blackboard.toStructuredFacts()
        let constraints: [RuleConstraint] = await context.blackboard.ruleConstraints
        var steps: [(String, String)] = []

        // Step 1: 理解发明
        let field: String = facts.technicalField.isEmpty ? "待补充" : facts.technicalField
        steps.append(("1. 理解发明", """
        技术领域: \(field)
        发明点数量: \(facts.inventionPoints.count)
        发明概述: \(facts.inventionPoints.joined(separator: "; "))
        """))

        // Step 2: 确定技术问题
        let problem: String = facts.problem.isEmpty ? "待从发明点中提炼" : facts.problem
        steps.append(("2. 确定技术问题", """
        实际解决的技术问题: \(problem)
        """))

        // Step 3: 检索现有技术
        let ruleTitles: String = context.rules.candidates.prefix(5)
            .map(\.title).joined(separator: "、")
        steps.append(("3. 检索对比文献", """
        适用规则/对比文献: \(ruleTitles.isEmpty ? "无" : ruleTitles)
        检索到规则数: \(context.rules.candidates.count)
        """))

        // Step 4: 分析区别特征
        let missingInfo: [String] = await context.blackboard.missingInfo
        let distinction: String = facts.inventionPoints.isEmpty
            ? "需进一步提取区别技术特征"
            : facts.inventionPoints.enumerated()
                .map { "  区别\($0.offset + 1): \($0.element)" }
                .joined(separator: "\n")
        steps.append(("4. 分析区别特征", distinction))

        // Step 5: 综合评估
        let mustCount: Int = constraints.filter { $0.requirement == .must }.count
        let shouldCount: Int = constraints.filter { $0.requirement == .should }.count
        let conflicts: String = context.rules.conflicts.isEmpty
            ? "无" : context.rules.conflicts.map { "  - \($0.description)" }
                .joined(separator: "\n")
        steps.append(("5. 综合评估", """
        约束统计: MUST=\(mustCount), SHOULD=\(shouldCount)
        规则冲突: \(conflicts)
        缺失信息: \(missingInfo.count) 项
        """))

        // Step 6: 得出结论
        let hasMissing: Bool = !missingInfo.isEmpty
        let conclusion: String = hasMissing
            ? "需补充信息后方可得出最终结论（缺失 \(missingInfo.count) 项）"
            : "基于现有事实和规则，可进入下一步流程"
        steps.append(("6. 结论", conclusion))

        let output: String = steps.map { "## \($0.0)\n\($0.1)" }.joined(separator: "\n\n")
        return ReasoningOutput(
            result: output,
            metadata: [
                "strategy": "six_step",
                "steps": "6",
                "has_missing_info": hasMissing ? "true" : "false"
            ]
        )
    }
}

// MARK: - Chain of Thought Strategy

/// 思维链推理 — 从用户请求出发，逐步推导到结论
public struct ChainOfThoughtStrategy: ReasoningStrategy {
    public let name: String = "chain_of_thought"

    public init() {}

    public func execute(context: ReasoningContext) async throws -> ReasoningOutput {
        let facts: StructuredFacts = await context.blackboard.toStructuredFacts()
        var chain: [String] = []

        // Link 1: 用户请求 → 技术领域
        chain.append("用户请求: \(context.userRequest.content.prefix(200))")
        chain.append("↓ 识别技术领域")
        chain.append("技术领域: \(facts.technicalField.isEmpty ? "待确定" : facts.technicalField)")

        // Link 2: 技术领域 → 发明点
        chain.append("↓ 提取发明点")
        if facts.inventionPoints.isEmpty {
            chain.append("发明点: 未提取到明确的发明点，需要进一步分析")
        } else {
            chain.append("发明点: \(facts.inventionPoints.count) 个")
            for point in facts.inventionPoints.prefix(3) {
                chain.append("  → \(point)")
            }
        }

        // Link 3: 发明点 → 适用规则
        chain.append("↓ 匹配适用规则")
        if context.rules.candidates.isEmpty {
            chain.append("适用规则: 无匹配")
        } else {
            chain.append("适用规则: \(context.rules.candidates.count) 条")
            for candidate in context.rules.candidates.prefix(3) {
                chain.append("  → \(candidate.title)")
            }
        }

        // Link 4: 规则 → 约束
        let constraints: [RuleConstraint] = await context.blackboard.ruleConstraints
        chain.append("↓ 推导约束")
        if constraints.isEmpty {
            chain.append("约束: 无")
        } else {
            chain.append("约束: \(constraints.count) 条")
            for constraint in constraints.prefix(3) {
                chain.append("  → [\(constraint.requirement.rawValue)] \(constraint.articleName)")
            }
        }

        // Link 5: 结论
        chain.append("↓ 得出结论")
        let problem: String = facts.problem.isEmpty ? "待确定" : facts.problem
        chain.append("结论: 针对技术问题「\(problem)」，已建立 \(facts.inventionPoints.count) 个发明点与 \(constraints.count) 条约束的映射")

        let output: String = chain.joined(separator: "\n")
        return ReasoningOutput(
            result: output,
            metadata: [
                "strategy": "chain_of_thought",
                "chain_length": "\(chain.count)",
                "invention_points": "\(facts.inventionPoints.count)"
            ]
        )
    }
}

// MARK: - Knowledge Graph Strategy

/// 知识图谱推理 — 基于 FactBlackboard 中的推理链
public struct KgReasoningStrategy: ReasoningStrategy {
    public let name: String = "kg_reasoning"

    public init() {}

    public func execute(context: ReasoningContext) async throws -> ReasoningOutput {
        let chains: [ReasoningChain] = await context.blackboard.reasoningChains
        let judgments: [ArticleJudgment] = await context.blackboard.articleJudgments

        var lines: [String] = ["## 知识图谱推理结果"]

        if !chains.isEmpty {
            lines.append("### 推理链 (\(chains.count) 条)")
            for chain in chains.prefix(10) {
                lines.append("  \(chain.from) → \(chain.toNode)")
                lines.append("    证据: \(chain.evidence)")
            }
        }

        if !judgments.isEmpty {
            lines.append("### 法条判断 (\(judgments.count) 条)")
            for judgment in judgments.prefix(5) {
                lines.append("  [\(judgment.articleName)] \(judgment.conclusion)")
            }
        }

        if chains.isEmpty && judgments.isEmpty {
            lines.append("尚无推理链和法条判断数据。请先运行 ReasoningWalker 或 FrameworkEngine。")
        }

        let output: String = lines.joined(separator: "\n")
        return ReasoningOutput(
            result: output,
            metadata: [
                "strategy": "kg_reasoning",
                "chains": "\(chains.count)",
                "judgments": "\(judgments.count)"
            ]
        )
    }
}

// MARK: - Strategy Registry

public actor StrategyRegistry {
    private var strategies: [String: any ReasoningStrategy] = [:]

    public init() {}

    public func register(_ strategy: any ReasoningStrategy) {
        strategies[strategy.name] = strategy
    }

    public func strategy(named name: String) -> (any ReasoningStrategy)? {
        strategies[name]
    }

    public func allStrategies() -> [String] {
        Array(strategies.keys)
    }

    public func registerDefaults() {
        register(ReactStrategy())
        register(SixStepStrategy())
        register(ChainOfThoughtStrategy())
        register(KgReasoningStrategy())
    }
}
