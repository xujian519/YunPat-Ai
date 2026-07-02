import XCTest

@testable import YunPatCore

// MARK: - RuntimeConfig Tests

final class RuntimeConfigTests: XCTestCase {

    func testDefaultValues() {
        let config = RuntimeConfig()
        XCTAssertEqual(config.maxIterations, 50)
        XCTAssertEqual(config.coopBudget, 128)
        XCTAssertEqual(config.maxSubAgents, 3)
        XCTAssertEqual(config.defaultModel, "deepseek-chat")
    }

    func testBuilderProducesCustomConfig() {
        let config = RuntimeConfigBuilder()
            .maxIterations(100)
            .coopBudget(256)
            .maxSubAgents(5)
            .build()
        XCTAssertEqual(config.maxIterations, 100)
        XCTAssertEqual(config.coopBudget, 256)
        XCTAssertEqual(config.maxSubAgents, 5)
        XCTAssertEqual(config.toolTimeout, 30)  // unchanged default
    }

    func testJSONRoundtrip() throws {
        let config = RuntimeConfigBuilder()
            .maxIterations(42)
            .verboseLogging(true)
            .build()
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RuntimeConfig.self, from: data)
        XCTAssertEqual(decoded.maxIterations, 42)
        XCTAssertEqual(decoded.verboseLogging, true)
    }

    func testLoadNonexistentReturnsDefault() {
        let nonexistent = URL(fileURLWithPath: "/tmp/nonexistent_config.json")
        let config = RuntimeConfig.load(from: nonexistent)
        XCTAssertEqual(config.maxIterations, 50)
    }
}

// MARK: - CoopScheduler Tests

final class CoopSchedulerTests: XCTestCase {

    func testBudgetExhaustion() async {
        let coop: CoopScheduler = CoopScheduler(budget: 5)
        var has: Bool = await coop.hasBudgetRemaining
        XCTAssertTrue(has)

        for _ in 0..<5 { await coop.proceed() }
        await coop.proceed()  // triggers yield + replenish

        has = await coop.hasBudgetRemaining
        XCTAssertTrue(has)
        let count: Int = await coop.yieldCount
        XCTAssertEqual(count, 1)
    }

    func testUnconstrained() async {
        let coop: CoopScheduler = CoopScheduler(budget: 5)
        for _ in 0..<4 { await coop.proceed() }
        var remaining: Int = await coop.budgetRemaining
        XCTAssertEqual(remaining, 1)

        let stillHas: Bool = await coop.unconstrained {
            await coop.proceed()
            return await coop.hasBudgetRemaining
        }
        XCTAssertTrue(stillHas)
        remaining = await coop.budgetRemaining
        XCTAssertEqual(remaining, 1)

        await coop.proceed()  // depletes, resets
        remaining = await coop.budgetRemaining
        XCTAssertEqual(remaining, 5)
    }
}

final class AgentMetricsTests: XCTestCase {

    func testConcurrentIncrements() async {
        let metrics: AgentMetrics = AgentMetrics()
        let concurrency: Int = 20
        let incsPerTask: Int = 50

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrency {
                group.addTask {
                    for _ in 0..<incsPerTask {
                        metrics.incToolCall()
                        metrics.addInputTokens(10)
                    }
                }
            }
        }
        let snap: MetricsSnapshot = metrics.snapshot()
        XCTAssertEqual(snap.toolCallCount, concurrency * incsPerTask)
        XCTAssertEqual(snap.llmInputTokens, concurrency * incsPerTask * 10)
    }

    func testResetZeroesAll() {
        let metrics: AgentMetrics = AgentMetrics()
        metrics.incToolCall()
        metrics.incStuckNudge()
        metrics.addInputTokens(100)
        metrics.reset()
        let snap: MetricsSnapshot = metrics.snapshot()
        XCTAssertEqual(snap.toolCallCount, 0)
        XCTAssertEqual(snap.stuckNudgeCount, 0)
        XCTAssertEqual(snap.llmInputTokens, 0)
    }

    func testLatencyAverage() {
        let metrics: AgentMetrics = AgentMetrics()
        metrics.recordLatency(ms: 100)
        metrics.recordLatency(ms: 200)
        XCTAssertEqual(metrics.snapshot().averageLatencyMs, 150)
    }
}

// MARK: - ToolCallState Tests

final class ToolCallStateTests: XCTestCase {

    func testTerminalDetection() {
        XCTAssertTrue(ToolCallState.completed.isTerminal)
        XCTAssertTrue(ToolCallState.failed.isTerminal)
        XCTAssertTrue(ToolCallState.cancelled.isTerminal)
        XCTAssertFalse(ToolCallState.queued.isTerminal)
        XCTAssertFalse(ToolCallState.executing.isTerminal)
    }

    func testCombinationStates() {
        let both: ToolCallState = [.executing, .awaitingUser]
        XCTAssertTrue(both.isActive)
        XCTAssertTrue(both.contains(.executing))
        XCTAssertTrue(both.contains(.awaitingUser))
        XCTAssertFalse(both.contains(.queued))
    }

    func testIdleIsZero() {
        XCTAssertTrue(ToolCallState.idle.isIdle)
        XCTAssertEqual(ToolCallState.idle.rawValue, 0)
    }
}

// MARK: - Bits Tests

final class BitsTests: XCTestCase {

    func testPackUnpackRoundtrip() {
        let (hiVal, loVal): (UInt32, UInt32) = (0xDEAD_BEEF, 0xCAFE_BABE)
        let (hi2, lo2): (UInt32, UInt32) = Bits.unpack(Bits.pack(hiVal, loVal))
        XCTAssertEqual(hi2, hiVal)
        XCTAssertEqual(lo2, loVal)
    }

    func testBitFlags() {
        var value: Int = 0
        Bits.set(&value, pos: 3)
        XCTAssertTrue(Bits.isSet(value, pos: 3))
        Bits.clear(&value, pos: 3)
        XCTAssertFalse(Bits.isSet(value, pos: 3))
        XCTAssertEqual(value, 0)
    }

    func testAlignUp() {
        XCTAssertEqual(Bits.alignUp(1, to: 8), 8)
        XCTAssertEqual(Bits.alignUp(8, to: 8), 8)
        XCTAssertEqual(Bits.alignUp(9, to: 8), 16)
    }
}

// MARK: - RandGenerator Tests

final class RandGeneratorTests: XCTestCase {

    func testDeterminism() {
        var rng1 = RandGenerator(seed: 42)
        var rng2 = RandGenerator(seed: 42)
        for _ in 0..<100 {
            XCTAssertEqual(rng1.next(), rng2.next())
        }
    }

    func testDifferentSeedsDiverge() {
        var rng1 = RandGenerator(seed: 1)
        var rng2 = RandGenerator(seed: 2)
        var allSame: Bool = true
        for _ in 0..<100 where rng1.next() != rng2.next() {
            allSame = false
            break
        }
        XCTAssertFalse(allSame)
    }
}

// MARK: - SyncWrapper Tests

final class SyncWrapperTests: XCTestCase {

    func testConsume() {
        XCTAssertEqual(SyncWrapper(42).consume(), 42)
    }
}
