import Foundation
import YunPatNetworking

// MARK: - RoutingStrategy

/// 路由策略 — 决定模型选择的目标函数
public enum RoutingStrategy: String, Sendable, Codable, CaseIterable {
    /// 平衡：在能力与成本之间取折中（默认）
    case balanced
    /// 廉价：优先最低成本
    case cheap
    /// 能力：优先最强模型
    case capable
    /// 本地优先：只选 ollama/mlx，无本地模型时拒绝
    case localOnly
    /// 案件预算：在预算内选能力最强，超预算时降级
    case caseBudget
}

// MARK: - RoutingConstraints

/// 路由约束 — 调用方可声明的硬性/软性偏好
public struct RoutingConstraints: Sendable {
    public let strategy: RoutingStrategy
    public let preferredProvider: ModelProvider?
    public let maxCostUsd: Double?
    public let requireTools: Bool
    public let requireVision: Bool
    public let estimatedInputTokens: Int

    public init(
        strategy: RoutingStrategy = .balanced,
        preferredProvider: ModelProvider? = nil,
        maxCostUsd: Double? = nil,
        requireTools: Bool = false,
        requireVision: Bool = false,
        estimatedInputTokens: Int = 0
    ) {
        self.strategy = strategy
        self.preferredProvider = preferredProvider
        self.maxCostUsd = maxCostUsd
        self.requireTools = requireTools
        self.requireVision = requireVision
        self.estimatedInputTokens = estimatedInputTokens
    }

    public static let `default` = RoutingConstraints()
}

// MARK: - RoutingRequest

/// 路由请求
public struct RoutingRequest: Sendable {
    public let content: String
    public let caseId: String?
    public let constraints: RoutingConstraints

    public init(
        content: String,
        caseId: String? = nil,
        constraints: RoutingConstraints = .default
    ) {
        self.content = content
        self.caseId = caseId
        self.constraints = constraints
    }
}

// MARK: - RoutingDecision

/// 路由决策结果
public struct RoutingDecision: Sendable {
    public let provider: ModelProvider
    public let model: String
    public let estimatedInputTokens: Int
    public let estimatedCostUsd: Double
    public let reason: String
    /// 是否经过回退链
    public let didFallback: Bool
    /// 回退链跳转次数
    public let fallbackDepth: Int

    public init(
        provider: ModelProvider,
        model: String,
        estimatedInputTokens: Int,
        estimatedCostUsd: Double,
        reason: String,
        didFallback: Bool = false,
        fallbackDepth: Int = 0
    ) {
        self.provider = provider
        self.model = model
        self.estimatedInputTokens = estimatedInputTokens
        self.estimatedCostUsd = estimatedCostUsd
        self.reason = reason
        self.didFallback = didFallback
        self.fallbackDepth = fallbackDepth
    }
}

/// 回退链通知 — 向 FallbackChainService 报告成功/失败
public enum FallbackReport: Sendable {
    case success
    case failure(Error)
}

// MARK: - ModelScore

/// 候选模型评分
private struct ModelScore: Sendable {
    let provider: ModelProvider
    let model: String
    let capabilityScore: Double
    let costScore: Double
    let estimatedCost: Double
}

// MARK: - RoutingEngine

/// 智能路由引擎 — 基于任务分类、模型能力、成本预算做动态模型选择
///
/// 对标 PilotDeck「smart routing」：在 YunPat-Ai 中按案件预算与任务类型自动选择模型。
/// 集成 FallbackChainService：主 provider 失败时自动依次回退至链中下一个启用的 provider。
public actor RoutingEngine {

    public static let shared: RoutingEngine = RoutingEngine(
        fallbackService: FallbackChainService.shared
    )

    private let budgetService: TokenBudgetService
    private let pricing: PricingTable
    private let fallbackService: FallbackChainService
    private var depth: Int = 0

    public init(
        budgetService: TokenBudgetService = TokenBudgetService(),
        pricing: PricingTable = PricingTable(),
        fallbackService: FallbackChainService
    ) {
        self.budgetService = budgetService
        self.pricing = pricing
        self.fallbackService = fallbackService
    }

    /// 基于请求内容做任务分类（沿用 SmartModelRouter 关键词规则）
    public static func classify(_ content: String) -> SmartModelRouter.TaskCategory {
        let lowercased: String = content.lowercased()
        let draftingKeywords: [String] = ["撰写", "权利要求", "说明书", "起草", "独立权利要求", "从属权利要求"]
        if draftingKeywords.contains(where: { lowercased.contains($0) }) { return .drafting }

        let retrievalKeywords: [String] = ["检索", "搜索", "查找", "查询", "法律状态", "专利号"]
        if retrievalKeywords.contains(where: { lowercased.contains($0) }) { return .retrieval }

        let analysisKeywords: [String] = ["分析", "创造性", "新颖性", "三步法", "侵权", "对比", "无效"]
        if analysisKeywords.contains(where: { lowercased.contains($0) }) { return .analysis }

        if lowercased.contains("总结") || lowercased.contains("摘要") || lowercased.contains("概括") {
            return .summary
        }
        return .general
    }

    /// 返回给定 provider 与任务类别的候选模型名
    public static func candidateModels(
        for category: SmartModelRouter.TaskCategory,
        provider: ModelProvider
    ) -> [String] {
        switch provider {
        case .deepseek:
            switch category {
            case .summary: return ["deepseek-chat"]
            case .drafting, .analysis: return ["deepseek-reasoner", "deepseek-chat"]
            case .retrieval, .general: return ["deepseek-chat"]
            }
        case .openai:
            switch category {
            case .summary: return ["gpt-4o-mini", "gpt-4o"]
            case .drafting, .analysis, .retrieval, .general: return ["gpt-4o", "gpt-4o-mini"]
            }
        case .anthropic:
            return ["claude-sonnet-4-20250514"]
        case .glm:
            switch category {
            case .summary: return ["glm-4-flash", "glm-4"]
            case .drafting, .analysis, .retrieval, .general: return ["glm-4", "glm-4-plus"]
            }
        case .qwen:
            return ["qwen-plus"]
        case .openrouter, .siliconflow, .mistral, .together:
            return [provider.defaultModel]
        case .ollama, .mlx:
            return [provider.defaultModel]
        }
    }

    /// 核心路由入口
    public func route(_ request: RoutingRequest) async -> RoutingDecision {
        let category: SmartModelRouter.TaskCategory = Self.classify(request.content)
        let providers: [ModelProvider] = Self.candidateProviders(
            strategy: request.constraints.strategy,
            preferred: request.constraints.preferredProvider
        )

        // 估算输入 token（用于成本估算，不影响实际调用）
        let estimatedInput: Int = max(
            request.constraints.estimatedInputTokens,
            TokenEstimator.estimate(text: request.content, provider: request.constraints.preferredProvider ?? .deepseek)
        )

        // 生成候选评分
        var candidates: [ModelScore] = []
        for provider in providers {
            let models: [String] = Self.candidateModels(for: category, provider: provider)
            for model in models {
                let capability: Double = capabilityScore(
                    provider: provider, model: model, category: category,
                    requireTools: request.constraints.requireTools,
                    requireVision: request.constraints.requireVision
                )
                let cost: Double = pricing.cost(
                    usage: Usage(promptTokens: estimatedInput, completionTokens: estimatedInput / 2, totalTokens: 0),
                    model: model
                )
                let costScore: Double = normalizeCostScore(cost)
                candidates.append(ModelScore(
                    provider: provider, model: model,
                    capabilityScore: capability, costScore: costScore, estimatedCost: cost
                ))
            }
        }

        // 按策略排序
        let sorted: [ModelScore] = Self.rank(candidates: candidates, strategy: request.constraints.strategy)

        // 案件预算检查：优先选择不超限的候选，否则降级
        let chosen: ModelScore = await selectWithinBudget(
            sorted: sorted,
            caseId: request.caseId,
            budgetStrategy: request.constraints.strategy
        )

        // 回退链：仅非 localOnly 策略时启用，当首选 provider 无可用候选时尝试
        if request.constraints.strategy != .localOnly, sorted.isEmpty {
            return await fallbackRoute(category: category, estimatedInput: estimatedInput, request: request)
        }

        let reason: String = buildReason(
            category: category, strategy: request.constraints.strategy,
            score: chosen, withinBudget: chosen.estimatedCost <= (request.constraints.maxCostUsd ?? .infinity)
        )

        return RoutingDecision(
            provider: chosen.provider,
            model: chosen.model,
            estimatedInputTokens: estimatedInput,
            estimatedCostUsd: chosen.estimatedCost,
            reason: reason
        )
    }

    /// 报告调用成功/失败以更新 FallbackChainService 状态
    public func reportFallback(_ report: FallbackReport) {
        switch report {
        case .success:
            fallbackService.recordSuccess()
        case .failure:
            _ = fallbackService.recordFailure()
        }
    }

    /// 当前预算快照（透传 budgetService）
    public func snapshot(caseId: String? = nil) async -> TokenBudgetSnapshot {
        await budgetService.snapshot(caseId: caseId)
    }

    /// 更新预算服务（调用成功后上报实际 usage）
    public func reportUsage(
        caseId: String?, provider: ModelProvider, model: String, usage: Usage
    ) async {
        await budgetService.recordUsage(
            caseId: caseId, provider: provider, model: model, usage: usage
        )
    }

    /// 重置案件预算
    public func resetCaseBudget(caseId: String) async {
        await budgetService.resetCase(caseId: caseId)
    }

    /// 重置全局预算
    public func resetGlobalBudget() async {
        await budgetService.resetGlobal()
    }

    // MARK: - Provider Filtering

    private static func candidateProviders(
        strategy: RoutingStrategy,
        preferred: ModelProvider?
    ) -> [ModelProvider] {
        if let preferred {
            return [preferred]
        }
        switch strategy {
        case .localOnly:
            return ModelProvider.allLocal
        case .cheap:
            return [.deepseek, .glm, .qwen, .openai, .anthropic]
        case .capable:
            return [.anthropic, .openai, .deepseek, .glm, .qwen]
        case .balanced, .caseBudget:
            return [.deepseek, .openai, .glm, .qwen, .anthropic]
        }
    }

    // MARK: - Scoring
}

// MARK: - Private Extensions

private extension RoutingEngine {
    func capabilityScore(
        provider: ModelProvider,
        model: String,
        category: SmartModelRouter.TaskCategory,
        requireTools: Bool,
        requireVision: Bool
    ) -> Double {
        let caps: ModelCapabilities = provider.defaultCapabilities
        var score: Double = 0.0

        switch category {
        case .drafting, .analysis:
            score += model.lowercased().contains("reasoner") || model.lowercased().contains("opus") ? 1.0 : 0.5
            score += Double(caps.maxContextTokens) / 200_000.0
        case .retrieval:
            score += Double(caps.maxContextTokens) / 200_000.0
            score += 0.3
        case .summary:
            score += 0.3
        case .general:
            score += 0.5
        }

        if requireTools, !caps.supportsToolCalling { score -= 1.0 }
        if requireVision, !caps.supportsVision { score -= 1.0 }

        return max(0, score)
    }

    func normalizeCostScore(_ cost: Double) -> Double {
        let reference: Double = 1.0
        return 1.0 / (1.0 + cost / reference)
    }

    static func rank(
        candidates: [ModelScore],
        strategy: RoutingStrategy
    ) -> [ModelScore] {
        switch strategy {
        case .cheap:
            return candidates.sorted {
                if $0.estimatedCost != $1.estimatedCost { return $0.estimatedCost < $1.estimatedCost }
                return $0.capabilityScore > $1.capabilityScore
            }
        case .capable:
            return candidates.sorted {
                if $0.capabilityScore != $1.capabilityScore { return $0.capabilityScore > $1.capabilityScore }
                return $0.estimatedCost < $1.estimatedCost
            }
        case .balanced, .caseBudget:
            return candidates.sorted {
                let score0: Double = $0.capabilityScore * 0.6 + $0.costScore * 0.4
                let score1: Double = $1.capabilityScore * 0.6 + $1.costScore * 0.4
                if score0 != score1 { return score0 > score1 }
                return $0.estimatedCost < $1.estimatedCost
            }
        case .localOnly:
            return candidates.sorted { $0.capabilityScore > $1.capabilityScore }
        }
    }
}

private extension RoutingEngine {
    func fallbackRoute(
        category: SmartModelRouter.TaskCategory,
        estimatedInput: Int,
        request: RoutingRequest
    ) async -> RoutingDecision {
        var depth: Int = 0
        while let provider = fallbackService.currentProvider {
            let models: [String] = Self.candidateModels(for: category, provider: provider)
            guard let model = models.first else {
                _ = fallbackService.switchToNext()
                depth += 1
                continue
            }
            let cost: Double = pricing.cost(
                usage: Usage(promptTokens: estimatedInput, completionTokens: estimatedInput / 2, totalTokens: 0),
                model: model
            )
            let score = ModelScore(
                provider: provider, model: model,
                capabilityScore: 0.5, costScore: normalizeCostScore(cost), estimatedCost: cost
            )
            let reason = buildReason(
                category: category, strategy: request.constraints.strategy,
                score: score, withinBudget: cost <= (request.constraints.maxCostUsd ?? .infinity)
            )
            return RoutingDecision(
                provider: provider, model: model,
                estimatedInputTokens: estimatedInput,
                estimatedCostUsd: cost, reason: reason,
                didFallback: depth > 0, fallbackDepth: depth
            )
        }
        return RoutingDecision(
            provider: .deepseek, model: ProviderDefinition.definition(for: .deepseek).defaultModel,
            estimatedInputTokens: estimatedInput, estimatedCostUsd: 0,
            reason: "fallback chain exhausted",
            didFallback: true, fallbackDepth: depth
        )
    }

    func selectWithinBudget(
        sorted: [ModelScore],
        caseId: String?,
        budgetStrategy: RoutingStrategy
    ) async -> ModelScore {
        guard let caseId else { return sorted.first ?? Self.fallbackScore() }

        let caseBudget: Int = await budgetService.remainingCaseBudget(caseId: caseId)
        let globalBudget: Int = await budgetService.remainingGlobalBudget()

        for candidate in sorted {
            let estimatedTokens: Int = candidate.estimatedCost > 0
                ? max(1, Int(candidate.estimatedCost * 1_000_000))
                : 1000
            if estimatedTokens <= caseBudget && estimatedTokens <= globalBudget {
                return candidate
            }
        }

        if budgetStrategy == .caseBudget || budgetStrategy == .cheap {
            return sorted.min { $0.estimatedCost < $1.estimatedCost } ?? sorted.first ?? Self.fallbackScore()
        }
        return sorted.first ?? Self.fallbackScore()
    }

    func buildReason(
        category: SmartModelRouter.TaskCategory,
        strategy: RoutingStrategy,
        score: ModelScore,
        withinBudget: Bool
    ) -> String {
        let budgetNote: String = withinBudget ? "预算内" : "预算紧张/超支"
        return "任务:\(category) | 策略:\(strategy) | 模型:\(score.provider.rawValue)/\(score.model) | \(budgetNote)"
    }
}

private extension RoutingEngine {
    static func fallbackScore() -> ModelScore {
        ModelScore(
            provider: .deepseek,
            model: ProviderDefinition.definition(for: .deepseek).defaultModel,
            capabilityScore: 0.5,
            costScore: 0.5,
            estimatedCost: 0
        )
    }
}
