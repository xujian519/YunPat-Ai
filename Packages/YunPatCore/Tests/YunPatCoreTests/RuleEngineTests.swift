import Foundation
import Testing

@testable import YunPatCore

struct RuleEngineTests {

    // MARK: - Helpers

    private func createTempVault() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    // MARK: - retrieveRules

    @Test func retrieveRules_conceptIndexMatch() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        let engine = RuleEngine(adapter: adapter, vectorSearch: .shared)

        // Create Concept Index with matching entries
        let wikiDir = vault.appendingPathComponent("Wiki")
        try FileManager.default.createDirectory(at: wikiDir, withIntermediateDirectories: true)

        try """
        # 概念索引
        - [[创造性判断]] 创造性
        - [[新颖性判断]] 新颖性
        """.write(to: wikiDir.appendingPathComponent("Concept-Index.md"), atomically: true, encoding: .utf8)

        // Create the actual wiki pages
        try "# 创造性判断\n\n三步法是判断创造性的核心方法。"
            .write(to: wikiDir.appendingPathComponent("创造性判断.md"), atomically: true, encoding: .utf8)
        try "# 新颖性判断\n\n单独对比原则。"
            .write(to: wikiDir.appendingPathComponent("新颖性判断.md"), atomically: true, encoding: .utf8)

        let facts = StructuredFacts(
            technicalField: "机械",
            problem: "创造性",
            inventionPoints: ["创造性判断"]
        )

        let retrievedRules: ApplicableRules = try await engine.retrieveRules(for: facts)

        #expect(!retrievedRules.candidates.isEmpty)
        #expect(retrievedRules.candidates.allSatisfy { !$0.title.isEmpty })
    }

    @Test func retrieveRules_moduleIndexFallback() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        let engine = RuleEngine(adapter: adapter, vectorSearch: .shared)

        // Do NOT create Concept-Index.md — step 1 finds nothing.
        // VectorSearch.shared has no embedHandler — step 2 semantic search returns nothing.
        // So step 3 (module index breadth fallback) kicks in for patentPractice, examinationGuide, laws.

        let wikiDir = vault.appendingPathComponent("Wiki")
        try FileManager.default.createDirectory(at: wikiDir, withIntermediateDirectories: true)

        // Create 专利实务 (patentPractice) module index with a wikilink
        let moduleDir = wikiDir.appendingPathComponent("专利实务")
        try FileManager.default.createDirectory(at: moduleDir, withIntermediateDirectories: true)
        try "- [[宽泛规则]]"
            .write(to: moduleDir.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)

        // Create the linked page
        try "# 宽泛规则\n\n适用于多种情况的通用规则。"
            .write(to: wikiDir.appendingPathComponent("宽泛规则.md"), atomically: true, encoding: .utf8)

        let facts2 = StructuredFacts(technicalField: "无关", problem: "", inventionPoints: [])
        let fallbackRules: ApplicableRules = try await engine.retrieveRules(for: facts2)

        #expect(!fallbackRules.candidates.isEmpty)
        #expect(fallbackRules.candidates.first?.title == "宽泛规则")
    }

    @Test func retrieveRules_noContent_returnsEmpty() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        let engine = RuleEngine(adapter: adapter, vectorSearch: .shared)

        // Empty vault — no indexes, no concept index
        let facts3 = StructuredFacts(technicalField: "机械", problem: "创造性", inventionPoints: ["创造性"])
        let emptyRules: ApplicableRules = try await engine.retrieveRules(for: facts3)

        #expect(emptyRules.candidates.isEmpty)
    }

    // MARK: - resolveConflicts

    @Test func resolveConflicts_prefersLowerSourceLevel() async {
        let vault = URL(fileURLWithPath: "/tmp/unused")
        let adapter = WikiAdapter(vaultPath: vault)
        let engine = RuleEngine(adapter: adapter)

        let highPriority = RuleCandidate(
            wikilink: "laws", title: "法律规则", content: "",
            source: .statute("法律"), sourceLevel: 1, score: 0.5
        )
        let lowPriority = RuleCandidate(
            wikilink: "doctrine", title: "学理观点", content: "",
            source: .doctrine, sourceLevel: 3, score: 0.9
        )

        let resolvedLevel: [RuleCandidate] = await engine.resolveConflicts([lowPriority, highPriority])

        #expect(resolvedLevel.count == 2)
        #expect(resolvedLevel[0].title == "法律规则")  // sourceLevel 1 comes first
        #expect(resolvedLevel[1].title == "学理观点")
    }

    @Test func resolveConflicts_sameSourceLevel_higherScoreFirst() async {
        let vault = URL(fileURLWithPath: "/tmp/unused")
        let adapter = WikiAdapter(vaultPath: vault)
        let engine = RuleEngine(adapter: adapter)

        let lowScore = RuleCandidate(
            wikilink: "a", title: "低分", content: "",
            source: .doctrine, sourceLevel: 3, score: 0.3
        )
        let highScore = RuleCandidate(
            wikilink: "b", title: "高分", content: "",
            source: .doctrine, sourceLevel: 3, score: 0.9
        )

        let resolvedScore: [RuleCandidate] = await engine.resolveConflicts([lowScore, highScore])

        #expect(resolvedScore.count == 2)
        #expect(resolvedScore[0].title == "高分")  // higher score first
        #expect(resolvedScore[1].title == "低分")
    }

    @Test func resolveConflicts_mixedCriteria() async {
        let vault = URL(fileURLWithPath: "/tmp/unused")
        let adapter = WikiAdapter(vaultPath: vault)
        let engine = RuleEngine(adapter: adapter)

        let cand1 = RuleCandidate(
            wikilink: "1", title: "L1H", content: "", source: .statute("法律"), sourceLevel: 1, score: 0.9)
        let cand2 = RuleCandidate(
            wikilink: "2", title: "L1L", content: "", source: .statute("法律"), sourceLevel: 1, score: 0.3)
        let cand3 = RuleCandidate(
            wikilink: "3", title: "L2H", content: "", source: .guideline("指南"), sourceLevel: 2, score: 0.8)
        let cand4 = RuleCandidate(
            wikilink: "4", title: "L3H", content: "", source: .doctrine, sourceLevel: 3, score: 0.7)

        let resolvedMixed: [RuleCandidate] = await engine.resolveConflicts([cand4, cand1, cand3, cand2])

        #expect(resolvedMixed.count == 4)
        #expect(resolvedMixed[0].title == "L1H")  // level 1, score 0.9
        #expect(resolvedMixed[1].title == "L1L")  // level 1, score 0.3
        #expect(resolvedMixed[2].title == "L2H")  // level 2, score 0.8
        #expect(resolvedMixed[3].title == "L3H")  // level 3, score 0.7
    }

    @Test func resolveConflicts_emptyArray_returnsEmpty() async {
        let vault = URL(fileURLWithPath: "/tmp/unused")
        let adapter = WikiAdapter(vaultPath: vault)
        let engine = RuleEngine(adapter: adapter)

        let resolvedEmpty: [RuleCandidate] = await engine.resolveConflicts([])
        #expect(resolvedEmpty.isEmpty)
    }
}
