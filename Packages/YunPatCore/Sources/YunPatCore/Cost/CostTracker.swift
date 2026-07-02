import Foundation
import YunPatNetworking

// MARK: - PricingTable

/// 模型单价表（美元 / 1M token）
///
/// 双轨预算的核心：熔断用 token（永远可靠），展示用 $（直观但依赖单价准确）。
/// 本地模型（ollama/mlx）不在表中，自动返回 0 单价。
/// 单价可能过期，仅用于成本估算展示，不影响 token 熔断的准确性。
public struct PricingTable: Sendable {

    public struct Rate: Sendable {
        public let inputPerMillion: Double
        public let outputPerMillion: Double
        public init(inputPerMillion: Double, outputPerMillion: Double) {
            self.inputPerMillion = inputPerMillion
            self.outputPerMillion = outputPerMillion
        }
    }

    private var rates: [String: Rate]

    public init(rates: [String: Rate] = [:]) {
        // 自定义值优先，合并默认表
        self.rates = Self.defaultRates
        for (key, value) in rates { self.rates[key] = value }
    }

    /// 查询模型单价：精确匹配 > 前缀匹配 > 0（本地/未知）
    public func rate(for model: String) -> Rate {
        if let rate = rates[model] { return rate }
        // 前缀匹配（如 deepseek-chat-xxx、gpt-4o-2024-xx）
        let prefixKey: String? = rates.keys
            .filter { model.hasPrefix($0) }
            .max(by: { $0.count < $1.count })
        if let key = prefixKey, let rate = rates[key] { return rate }
        return Rate(inputPerMillion: 0, outputPerMillion: 0)
    }

    /// 计算 usage 的美元成本
    public func cost(usage: Usage, model: String) -> Double {
        let rate: Rate = rate(for: model)
        let inCost: Double = Double(usage.promptTokens) * rate.inputPerMillion / 1_000_000
        let outCost: Double = Double(usage.completionTokens) * rate.outputPerMillion / 1_000_000
        return inCost + outCost
    }

    /// 默认单价（基于 2024-2025 公开价格近似值，可被 init 覆盖）
    public static let defaultRates: [String: Rate] = [
        "deepseek-chat": Rate(inputPerMillion: 0.27, outputPerMillion: 1.10),
        "deepseek-reasoner": Rate(inputPerMillion: 0.55, outputPerMillion: 2.19),
        "gpt-4o": Rate(inputPerMillion: 2.50, outputPerMillion: 10.00),
        "gpt-4o-mini": Rate(inputPerMillion: 0.15, outputPerMillion: 0.60),
        "gpt-4.1": Rate(inputPerMillion: 2.00, outputPerMillion: 8.00),
        "gpt-4.1-mini": Rate(inputPerMillion: 0.40, outputPerMillion: 1.60),
        "claude-3-5-sonnet": Rate(inputPerMillion: 3.00, outputPerMillion: 15.00),
        "claude-3-5-haiku": Rate(inputPerMillion: 0.80, outputPerMillion: 4.00),
        "claude-sonnet-4": Rate(inputPerMillion: 3.00, outputPerMillion: 15.00),
        "glm-4": Rate(inputPerMillion: 0.50, outputPerMillion: 1.40),
        "glm-4-plus": Rate(inputPerMillion: 3.52, outputPerMillion: 3.52)
    ]
}

// MARK: - CostSnapshot

/// 成本累计快照（不可变，供 UI / Trace 读取）
public struct CostSnapshot: Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int
    public let costUsd: Double

    public init(inputTokens: Int, outputTokens: Int, costUsd: Double) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = inputTokens + outputTokens
        self.costUsd = costUsd
    }

    public var isZero: Bool { totalTokens == 0 && costUsd == 0 }

    public static let zero: CostSnapshot = CostSnapshot(inputTokens: 0, outputTokens: 0, costUsd: 0)
}

// MARK: - CostTracker

/// 成本追踪器（actor）— 双轨预算的核心
///
/// - 内部按 token 累加，达 `maxBudgetTokens` 触发熔断（数据源来自 Provider usage，稳定可靠）
/// - 同时按 PricingTable 换算 $，供 Trace/UI 展示（单价可能过期，仅展示用）
///
/// 线程安全：actor 隔离，可在多 surface / 子 Agent 间共享。
/// 零开销：未注入时（nil）调用方短路，不创建实例。
public actor CostTracker {

    private var inputTokens: Int = 0
    private var outputTokens: Int = 0
    private var costUsd: Double = 0
    private let pricing: PricingTable
    public let maxBudgetTokens: Int

    public init(pricing: PricingTable = PricingTable(), maxBudgetTokens: Int = 200_000) {
        self.pricing = pricing
        self.maxBudgetTokens = maxBudgetTokens
    }

    /// 上报一次 LLM 调用的 usage，返回本次调用的美元成本（usage 为 nil 时返回 0）
    @discardableResult
    public func record(usage: Usage?, model: String) -> Double {
        guard let usage else { return 0 }
        inputTokens += usage.promptTokens
        outputTokens += usage.completionTokens
        let delta: Double = pricing.cost(usage: usage, model: model)
        costUsd += delta
        return delta
    }

    /// 当前累计快照
    public var snapshot: CostSnapshot {
        CostSnapshot(inputTokens: inputTokens, outputTokens: outputTokens, costUsd: costUsd)
    }

    /// 是否超出 token 预算（maxBudgetTokens == 0 表示不限制）
    public var isOverBudget: Bool {
        guard maxBudgetTokens > 0 else { return false }
        return (inputTokens + outputTokens) > maxBudgetTokens
    }

    /// 已用预算百分比（0-100，无预算限制时返回 0）
    public var budgetUsagePercent: Double {
        guard maxBudgetTokens > 0 else { return 0 }
        return min(100, Double(inputTokens + outputTokens) / Double(maxBudgetTokens) * 100)
    }

    /// 重置（跨 session）
    public func reset() {
        inputTokens = 0
        outputTokens = 0
        costUsd = 0
    }
}
