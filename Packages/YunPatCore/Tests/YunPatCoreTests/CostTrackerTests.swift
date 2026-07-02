import XCTest
import YunPatNetworking

@testable import YunPatCore

final class CostTrackerTests: XCTestCase {

    // MARK: - Token 累加

    func test_record_accumulatesTokens() async {
        let tracker: CostTracker = CostTracker(maxBudgetTokens: 10_000)
        _ = await tracker.record(
            usage: Usage(promptTokens: 100, completionTokens: 50, totalTokens: 150), model: "deepseek-chat")
        _ = await tracker.record(
            usage: Usage(promptTokens: 200, completionTokens: 100, totalTokens: 300), model: "deepseek-chat")
        let snap: CostSnapshot = await tracker.snapshot
        XCTAssertEqual(snap.inputTokens, 300)
        XCTAssertEqual(snap.outputTokens, 150)
        XCTAssertEqual(snap.totalTokens, 450)
    }

    func test_nilUsage_ignored_returnsZero() async {
        let tracker: CostTracker = CostTracker(maxBudgetTokens: 10_000)
        let delta: Double = await tracker.record(usage: nil, model: "test")
        XCTAssertEqual(delta, 0)
        let snap: CostSnapshot = await tracker.snapshot
        XCTAssertTrue(snap.isZero)
    }

    // MARK: - $ 成本换算（PricingTable）

    func test_record_accumulatesCostUsd() async {
        let tracker: CostTracker = CostTracker(maxBudgetTokens: 10_000_000)
        // deepseek-chat: input $0.27/1M → 1M input tokens = $0.27
        _ = await tracker.record(
            usage: Usage(promptTokens: 1_000_000, completionTokens: 0, totalTokens: 1_000_000), model: "deepseek-chat")
        // output $1.10/1M → 1M output tokens = $1.10
        _ = await tracker.record(
            usage: Usage(promptTokens: 0, completionTokens: 1_000_000, totalTokens: 1_000_000), model: "deepseek-chat")
        let snap: CostSnapshot = await tracker.snapshot
        XCTAssertEqual(snap.costUsd, 1.37, accuracy: 0.001)  // 0.27 + 1.10
    }

    func test_localModel_zeroCost() async {
        let tracker: CostTracker = CostTracker(maxBudgetTokens: 10_000)
        _ = await tracker.record(
            usage: Usage(promptTokens: 1000, completionTokens: 500, totalTokens: 1500), model: "llama3")
        let snap: CostSnapshot = await tracker.snapshot
        XCTAssertEqual(snap.costUsd, 0)
        XCTAssertEqual(snap.totalTokens, 1500)
    }

    func test_record_returnsIncrementalCost() async {
        let tracker: CostTracker = CostTracker(maxBudgetTokens: 10_000_000)
        let cost1: Double = await tracker.record(
            usage: Usage(promptTokens: 1_000_000, completionTokens: 0, totalTokens: 1_000_000), model: "deepseek-chat")
        let cost2: Double = await tracker.record(
            usage: Usage(promptTokens: 0, completionTokens: 1_000_000, totalTokens: 1_000_000), model: "deepseek-chat")
        XCTAssertEqual(cost1, 0.27, accuracy: 0.001)  // 本次增量
        XCTAssertEqual(cost2, 1.10, accuracy: 0.001)
    }

    // MARK: - 预算熔断

    func test_isOverBudget_whenExceeded() async {
        let tracker: CostTracker = CostTracker(maxBudgetTokens: 100)
        _ = await tracker.record(usage: Usage(promptTokens: 50, completionTokens: 60, totalTokens: 110), model: "test")
        let over: Bool = await tracker.isOverBudget
        XCTAssertTrue(over)
    }

    func test_isUnderBudget_whenNotExceeded() async {
        let tracker: CostTracker = CostTracker(maxBudgetTokens: 1000)
        _ = await tracker.record(usage: Usage(promptTokens: 100, completionTokens: 50, totalTokens: 150), model: "test")
        let over: Bool = await tracker.isOverBudget
        XCTAssertFalse(over)
    }

    func test_zeroBudget_disablesLimit() async {
        let tracker: CostTracker = CostTracker(maxBudgetTokens: 0)
        _ = await tracker.record(
            usage: Usage(promptTokens: 999_999, completionTokens: 999_999, totalTokens: 1_999_998), model: "test")
        let over: Bool = await tracker.isOverBudget
        XCTAssertFalse(over)
    }

    func test_budgetUsagePercent() async {
        let tracker: CostTracker = CostTracker(maxBudgetTokens: 1000)
        _ = await tracker.record(
            usage: Usage(promptTokens: 300, completionTokens: 200, totalTokens: 500), model: "test")
        let pct: Double = await tracker.budgetUsagePercent
        XCTAssertEqual(pct, 50, accuracy: 0.1)
    }

    // MARK: - reset

    func test_reset_clearsAccumulation() async {
        let tracker: CostTracker = CostTracker(maxBudgetTokens: 10_000)
        _ = await tracker.record(usage: Usage(promptTokens: 100, completionTokens: 50, totalTokens: 150), model: "test")
        await tracker.reset()
        let snap: CostSnapshot = await tracker.snapshot
        XCTAssertTrue(snap.isZero)
    }

    // MARK: - PricingTable

    func test_pricingTable_exactMatch() {
        let table: PricingTable = PricingTable()
        let rate: PricingTable.Rate = table.rate(for: "gpt-4o")
        XCTAssertEqual(rate.inputPerMillion, 2.50, accuracy: 0.001)
        XCTAssertEqual(rate.outputPerMillion, 10.00, accuracy: 0.001)
    }

    func test_pricingTable_prefixMatch_versionedModel() {
        let table: PricingTable = PricingTable()
        let rate: PricingTable.Rate = table.rate(for: "gpt-4o-2024-08-06")
        XCTAssertEqual(rate.inputPerMillion, 2.50, accuracy: 0.001)
    }

    func test_pricingTable_unknownModel_zeroRate() {
        let table: PricingTable = PricingTable()
        let rate: PricingTable.Rate = table.rate(for: "some-unknown-model")
        XCTAssertEqual(rate.inputPerMillion, 0)
        XCTAssertEqual(rate.outputPerMillion, 0)
    }

    func test_pricingTable_customOverride() {
        let table: PricingTable = PricingTable(rates: [
            "deepseek-chat": PricingTable.Rate(inputPerMillion: 999, outputPerMillion: 888)
        ])
        let rate: PricingTable.Rate = table.rate(for: "deepseek-chat")
        XCTAssertEqual(rate.inputPerMillion, 999)
        XCTAssertEqual(rate.outputPerMillion, 888)
    }

    // MARK: - RuntimeConfig 集成

    func test_runtimeConfig_defaultBudget() {
        let config: RuntimeConfig = RuntimeConfig()
        XCTAssertEqual(config.maxBudgetTokens, 200_000)
    }

    func test_runtimeConfigBuilder_budget() {
        let config: RuntimeConfig = RuntimeConfigBuilder().maxBudgetTokens(50_000).build()
        XCTAssertEqual(config.maxBudgetTokens, 50_000)
    }
}
