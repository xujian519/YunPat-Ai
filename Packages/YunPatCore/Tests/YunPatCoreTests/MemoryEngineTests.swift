import XCTest

@testable import YunPatCore

final class MemoryEngineTests: XCTestCase {

    // MARK: - Layer 1: WorkingMemory

    func testWorkingMemory_setAndRetrieveGoal() async {
        let engine: MemoryEngine = MemoryEngine()
        await engine.setGoal("draft claims for IoT sensor patent")
        let goal: String = await engine.currentGoal()
        XCTAssertEqual(goal, "draft claims for IoT sensor patent")
    }

    func testWorkingMemory_hypothesesAndScratchpad() async {
        let engine: MemoryEngine = MemoryEngine()
        await engine.addHypothesis("独立权利要求可能缺乏创造性")
        await engine.noteToScratchpad("需要检索对比文件")
        let hyps: [String] = await engine.activeHypotheses()
        let notes: [String] = await engine.scratchpad()
        XCTAssertEqual(hyps.count, 1)
        XCTAssertEqual(notes.count, 1)
    }

    func testWorkingMemory_intermediateResults() async {
        let engine: MemoryEngine = MemoryEngine()
        await engine.setResult("3项权利要求", forKey: "claimCount")
        let count: String? = await engine.result(forKey: "claimCount")
        XCTAssertEqual(count, "3项权利要求")
    }

    func testWorkingMemory_resetClearsEverything() async {
        let engine: MemoryEngine = MemoryEngine()
        await engine.setGoal("test")
        await engine.addHypothesis("h1")
        await engine.noteToScratchpad("n1")
        await engine.setResult("v", forKey: "key")
        await engine.resetWorkingMemory()
        let goal: String = await engine.currentGoal()
        let hyps: [String] = await engine.activeHypotheses()
        let notes: [String] = await engine.scratchpad()
        let result: String? = await engine.result(forKey: "key")
        XCTAssertEqual(goal, "")
        XCTAssertEqual(hyps.count, 0)
        XCTAssertEqual(notes.count, 0)
        XCTAssertNil(result)
    }

    // MARK: - Layer 2: SessionFacts

    func testSessionFacts_addAndFilter() async {
        let engine: MemoryEngine = MemoryEngine()
        await engine.addSessionFact("传感器采用MEMS结构", category: .technicalFeature)
        await engine.addSessionFact("根据专利法第22条第3款", category: .legalRule)
        await engine.addSessionFact("建议增加方法权利要求", category: .strategy)

        let all: [SessionFact] = await engine.pendingSessionFacts()
        XCTAssertEqual(all.count, 3)

        let tech: [SessionFact] = await engine.sessionFacts(ofCategory: .technicalFeature)
        XCTAssertEqual(tech.count, 1)
        XCTAssertEqual(tech.first?.fact, "传感器采用MEMS结构")
    }

    // MARK: - Layer 3: CaseContext

    func testCaseContext_saveAndLoad() async throws {
        let engine: MemoryEngine = MemoryEngine()
        let ctx: CaseContext = CaseContext(
            caseId: "test-case-1",
            applicationNumber: "CN202410000001.0",
            technicalField: "半导体制造",
            inventionPoints: ["新型蚀刻工艺", "降低缺陷率"],
            keyReferences: ["US1234567B2"],
            openIssues: ["需要补充实验数据"]
        )
        try await engine.saveCaseContext(ctx)
        let loaded: CaseContext? = await engine.loadCaseContext("test-case-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.applicationNumber, "CN202410000001.0")
        XCTAssertEqual(loaded?.inventionPoints.count, 2)
    }

    func testCaseContext_remove() async throws {
        let engine: MemoryEngine = MemoryEngine()
        let ctx: CaseContext = CaseContext(caseId: "to-remove")
        try await engine.saveCaseContext(ctx)
        await engine.removeCaseContext("to-remove")
        let loaded: CaseContext? = await engine.loadCaseContext("to-remove")
        XCTAssertNil(loaded)
    }

    // MARK: - Layer 4: LongTermMemory

    func testLongTermMemory_addPrecedent() async throws {
        let engine: MemoryEngine = MemoryEngine()
        try await engine.addLegalPrecedent("三步法判断创造性")
        let ltm: LongTermMemory = await engine.loadLongTermMemory()
        XCTAssertTrue(ltm.legalPrecedents.contains("三步法判断创造性"))
    }

    func testLongTermMemory_addStrategy() async throws {
        let engine: MemoryEngine = MemoryEngine()
        try await engine.addSuccessfulStrategy("多层次防御性布局")
        let ltm: LongTermMemory = await engine.loadLongTermMemory()
        XCTAssertTrue(ltm.successfulStrategies.contains("多层次防御性布局"))
    }

    func testLongTermMemory_deduplicatesOnAdd() async throws {
        let engine: MemoryEngine = MemoryEngine()
        try await engine.addPitfall("避免功能性限定")
        try await engine.addPitfall("避免功能性限定")
        let ltm: LongTermMemory = await engine.loadLongTermMemory()
        XCTAssertEqual(ltm.learnedPitfalls.count, 1)
    }

    // MARK: - Layer 5: GlobalMemory

    func testGlobalMemory_saveAndLoad() async throws {
        let engine: MemoryEngine = MemoryEngine()
        let memory: GlobalMemory = GlobalMemory(
            writingStyle: "简洁法律文书风格",
            terminologyPreferences: ["传感器": "感测单元"],
            preferredProviders: ["deepseek", "anthropic"]
        )
        try await engine.saveGlobalMemory(memory)
        let loaded: GlobalMemory = await engine.loadGlobalMemory()
        XCTAssertEqual(loaded.writingStyle, "简洁法律文书风格")
        XCTAssertEqual(loaded.terminologyPreferences["传感器"], "感测单元")
    }

    // MARK: - Consolidation

    func testConsolidate_clearsSessionFactsAndSavesCaseContext() async throws {
        let engine: MemoryEngine = MemoryEngine()
        await engine.addSessionFact("无线充电系统", category: .technicalFeature)
        await engine.addSessionFact("磁共振耦合", category: .technicalFeature)
        await engine.addSessionFact("专利法第22条第3款", category: .legalRule)

        let ctx: CaseContext = try await engine.consolidate()
        XCTAssertEqual(ctx.technicalField, "无线充电系统")
        XCTAssertEqual(ctx.inventionPoints.count, 2)
        XCTAssertEqual(ctx.keyReferences.count, 1)

        let remaining: [SessionFact] = await engine.pendingSessionFacts()
        XCTAssertEqual(remaining.count, 0)
    }

    func testConsolidateDeep_promotesStrategiesToLongTermMemory() async throws {
        let engine: MemoryEngine = MemoryEngine()
        await engine.addSessionFact("AI辅助专利检索方法", category: .technicalFeature)
        await engine.addSessionFact("环形多层权利要求布局", category: .strategy)

        let result: (CaseContext, LongTermMemory) = try await engine.consolidateDeep()
        let ctx: CaseContext = result.0
        let ltm: LongTermMemory = result.1
        XCTAssertEqual(ctx.technicalField, "AI辅助专利检索方法")
        XCTAssertTrue(ltm.successfulStrategies.contains("环形多层权利要求布局"))

        let remaining: [SessionFact] = await engine.pendingSessionFacts()
        XCTAssertEqual(remaining.count, 0)
    }

    // MARK: - Full 5-Layer Integration

    func testFiveLayerIntegration() async throws {
        let engine: MemoryEngine = MemoryEngine()

        // Layer 1: Working
        await engine.setGoal("撰写高质量专利权利要求")
        await engine.addHypothesis("新颖性不存在问题")
        await engine.noteToScratchpad("先检查对比文件D1的公开日")
        let goal: String = await engine.currentGoal()
        XCTAssertFalse(goal.isEmpty)

        // Layer 2: Session
        await engine.addSessionFact("柔性显示屏折叠机构", category: .technicalFeature)
        await engine.addSessionFact("D1公开了铰链结构但未公开弹性恢复单元", category: .decision)

        // Layer 3: Case
        let ctx: CaseContext = try await engine.consolidate()
        XCTAssertFalse(ctx.inventionPoints.isEmpty)

        // Layer 4: LongTerm
        try await engine.addSuccessfulStrategy("从技术效果反推技术问题")
        let ltm: LongTermMemory = await engine.loadLongTermMemory()
        XCTAssertFalse(ltm.successfulStrategies.isEmpty)

        // Layer 5: Global
        try await engine.saveGlobalMemory(GlobalMemory(writingStyle: "权威学术风格"))
        let globalMemory: GlobalMemory = await engine.loadGlobalMemory()
        XCTAssertEqual(globalMemory.writingStyle, "权威学术风格")
    }
}
