import Foundation
import YunPatNetworking

// MARK: - TokenBudgetConfig

/// 预算配置 — 全局与案件级 token/美元预算
public struct TokenBudgetConfig: Sendable, Codable, Equatable {
    /// 全局月度 token 预算（0 = 不限制）
    public var globalMonthlyTokens: Int
    /// 单个案件累计 token 预算（0 = 不限制）
    public var perCaseTokens: Int
    /// 单次调用最大 token 预算（0 = 不限制）
    public var perRequestTokens: Int
    /// 全局月度美元预算（0 = 不限制）
    public var globalMonthlyUsd: Double
    /// 单个案件美元预算（0 = 不限制）
    public var perCaseUsd: Double

    public init(
        globalMonthlyTokens: Int = 1_000_000,
        perCaseTokens: Int = 200_000,
        perRequestTokens: Int = 50_000,
        globalMonthlyUsd: Double = 50.0,
        perCaseUsd: Double = 10.0
    ) {
        self.globalMonthlyTokens = globalMonthlyTokens
        self.perCaseTokens = perCaseTokens
        self.perRequestTokens = perRequestTokens
        self.globalMonthlyUsd = globalMonthlyUsd
        self.perCaseUsd = perCaseUsd
    }

    public static let `default` = TokenBudgetConfig()
}

// MARK: - TokenBudgetSnapshot

/// 预算快照 — 供 UI/熔断决策读取
public struct TokenBudgetSnapshot: Sendable {
    public let caseId: String?
    public let usedTokens: Int
    public let usedUsd: Double
    public let caseBudgetTokens: Int
    public let caseBudgetUsd: Double
    public let globalBudgetTokens: Int
    public let globalBudgetUsd: Double
    public let remainingTokens: Int
    public let remainingUsd: Double

    public init(
        caseId: String?,
        usedTokens: Int,
        usedUsd: Double,
        caseBudgetTokens: Int,
        caseBudgetUsd: Double,
        globalBudgetTokens: Int,
        globalBudgetUsd: Double
    ) {
        self.caseId = caseId
        self.usedTokens = usedTokens
        self.usedUsd = usedUsd
        self.caseBudgetTokens = caseBudgetTokens
        self.caseBudgetUsd = caseBudgetUsd
        self.globalBudgetTokens = globalBudgetTokens
        self.globalBudgetUsd = globalBudgetUsd
        self.remainingTokens = max(0, min(globalBudgetTokens - usedTokens, caseBudgetTokens - usedTokens))
        self.remainingUsd = max(0, min(globalBudgetUsd - usedUsd, caseBudgetUsd - usedUsd))
    }

    public var percentTokens: Double {
        guard caseBudgetTokens > 0 else { return 0 }
        return min(100, Double(usedTokens) / Double(caseBudgetTokens) * 100)
    }

    public var percentUsd: Double {
        guard caseBudgetUsd > 0 else { return 0 }
        return min(100, Double(usedUsd) / Double(caseBudgetUsd) * 100)
    }

    public var isOverBudget: Bool {
        remainingTokens == 0 && caseBudgetTokens > 0
    }
}

// MARK: - TokenBudgetService

/// Token 预算服务 — 案件级 + 全局级预算跟踪
///
/// 对标 PilotDeck「always-on execution」中的成本控制：每次调用前检查预算，调用后累加 usage。
public actor TokenBudgetService {

    private let config: TokenBudgetConfig
    private var caseTrackers: [String: CostTracker] = [:]
    private var globalTracker: CostTracker
    private let store: TokenUsageStore

    public init(
        config: TokenBudgetConfig = .default,
        store: TokenUsageStore = TokenUsageStore()
    ) {
        self.config = config
        self.store = store
        self.globalTracker = CostTracker(maxBudgetTokens: config.globalMonthlyTokens)
    }

    /// 预检查本次调用是否会在预算内
    public func canProceed(
        caseId: String?,
        estimatedTokens: Int,
        estimatedCostUsd: Double
    ) async -> Bool {
        if let caseId {
            let tracker: CostTracker = tracker(for: caseId)
            let snap: CostSnapshot = await tracker.snapshot
            if config.perCaseTokens > 0,
               snap.totalTokens + estimatedTokens > config.perCaseTokens {
                return false
            }
            if config.perCaseUsd > 0,
               snap.costUsd + estimatedCostUsd > config.perCaseUsd {
                return false
            }
        }
        let globalSnap: CostSnapshot = await globalTracker.snapshot
        if config.globalMonthlyTokens > 0,
           globalSnap.totalTokens + estimatedTokens > config.globalMonthlyTokens {
            return false
        }
        if config.globalMonthlyUsd > 0,
           globalSnap.costUsd + estimatedCostUsd > config.globalMonthlyUsd {
            return false
        }
        return true
    }

    /// 记录一次实际 LLM 调用 usage
    public func recordUsage(
        caseId: String?,
        provider: ModelProvider,
        model: String,
        usage: Usage
    ) async {
        let cost: Double = PricingTable().cost(usage: usage, model: model)
        if let caseId {
            let tracker: CostTracker = tracker(for: caseId)
            await tracker.record(usage: usage, model: model)
        }
        await globalTracker.record(usage: usage, model: model)
        try? await store.append(TokenUsageRecord(
            id: UUID(),
            caseId: caseId,
            provider: provider.rawValue,
            model: model,
            inputTokens: usage.promptTokens,
            outputTokens: usage.completionTokens,
            costUsd: cost,
            timestamp: Date()
        ))
    }

    /// 当前案件剩余 token 预算（取 case/global 较小值）
    public func remainingCaseBudget(caseId: String) async -> Int {
        let tracker: CostTracker = tracker(for: caseId)
        let snap: CostSnapshot = await tracker.snapshot
        let caseRemaining: Int = config.perCaseTokens > 0 ? max(0, config.perCaseTokens - snap.totalTokens) : .max
        let globalRemaining: Int = config.globalMonthlyTokens > 0
            ? max(0, config.globalMonthlyTokens - snap.totalTokens) : .max
        return min(caseRemaining, globalRemaining)
    }

    /// 全局剩余 token 预算
    public func remainingGlobalBudget() async -> Int {
        let snap: CostSnapshot = await globalTracker.snapshot
        guard config.globalMonthlyTokens > 0 else { return .max }
        return max(0, config.globalMonthlyTokens - snap.totalTokens)
    }

    /// 当前预算快照
    public func snapshot(caseId: String? = nil) async -> TokenBudgetSnapshot {
        let globalSnap: CostSnapshot = await globalTracker.snapshot
        let caseSnap: CostSnapshot
        if let caseId {
            caseSnap = await tracker(for: caseId).snapshot
        } else {
            caseSnap = globalSnap
        }
        return TokenBudgetSnapshot(
            caseId: caseId,
            usedTokens: caseSnap.totalTokens,
            usedUsd: caseSnap.costUsd,
            caseBudgetTokens: config.perCaseTokens,
            caseBudgetUsd: config.perCaseUsd,
            globalBudgetTokens: config.globalMonthlyTokens,
            globalBudgetUsd: config.globalMonthlyUsd
        )
    }

    /// 重置案件累计（结案时调用）
    public func resetCase(caseId: String) async {
        caseTrackers[caseId] = CostTracker(maxBudgetTokens: config.perCaseTokens)
    }

    /// 重置全局累计（新月/新周期）
    public func resetGlobal() async {
        await globalTracker.reset()
    }

    // MARK: - Private

    private func tracker(for caseId: String) -> CostTracker {
        if let tracker = caseTrackers[caseId] { return tracker }
        let tracker: CostTracker = CostTracker(maxBudgetTokens: config.perCaseTokens)
        caseTrackers[caseId] = tracker
        return tracker
    }
}
