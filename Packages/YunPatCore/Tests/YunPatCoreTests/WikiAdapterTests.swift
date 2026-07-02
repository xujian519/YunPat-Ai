import Foundation
import Testing

@testable import YunPatCore

struct WikiAdapterTests {

    // MARK: - Helpers

    private func createTempVault() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    // MARK: - Card Operations

    @Test func readCard_returnsContent() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        let cardsDir = vault.appendingPathComponent("Wiki/Cards")
        try FileManager.default.createDirectory(at: cardsDir, withIntermediateDirectories: true)
        try "# 测试卡片\n\n卡片内容正文".write(
            to: cardsDir.appendingPathComponent("readCardTest.md"), atomically: true, encoding: .utf8)

        let content: String = try await adapter.readCard("readCardTest")

        #expect(content.contains("测试卡片"))
        #expect(content.contains("卡片内容正文"))
    }

    @Test func readCard_nonexistent_returnsEmpty() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)

        let content: String = try await adapter.readCard("nonexistent")
        #expect(content.isEmpty)
    }

    @Test func createCard_createsFileWithFrontmatter() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        try await adapter.createCard(name: "createCardTest", content: "卡片正文")

        let cardsDir = vault.appendingPathComponent("Wiki/Cards")
        let cardURL = cardsDir.appendingPathComponent("createCardTest.md")
        #expect(FileManager.default.fileExists(atPath: cardURL.path))

        let content = try String(contentsOf: cardURL, encoding: .utf8)
        #expect(content.contains("name: createCardTest"))
        #expect(content.contains("卡片正文"))
        #expect(content.hasPrefix("---"))
    }

    @Test func deprecateCard_renamesToDeprecated() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        try await adapter.createCard(name: "deprecateCardTest", content: "待废弃")
        try await adapter.deprecateCard(name: "deprecateCardTest")

        let original = vault.appendingPathComponent("Wiki/Cards/deprecateCardTest.md")
        let deprecated = vault.appendingPathComponent("Wiki/Cards/deprecateCardTest.md.deprecated")

        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(FileManager.default.fileExists(atPath: deprecated.path))
    }

    @Test func deprecateCard_nonexistent_doesNotThrow() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)

        // Should not throw even though card doesn't exist
        try await adapter.deprecateCard(name: "nonexistent")
    }

    // MARK: - Semantic Search

    @Test func semanticSearch_returnsMatchingFiles() throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        let wikiDir = vault.appendingPathComponent("Wiki")
        try FileManager.default.createDirectory(at: wikiDir, withIntermediateDirectories: true)

        try "# 创造性判断\n\n三步法是判断创造性的核心方法。"
            .write(to: wikiDir.appendingPathComponent("创造性判断.md"), atomically: true, encoding: .utf8)
        try "# 新颖性判断\n\n单独对比原则是判断新颖性的基础。"
            .write(to: wikiDir.appendingPathComponent("新颖性判断.md"), atomically: true, encoding: .utf8)

        let results = try adapter.semanticSearch(query: "创造性")

        #expect(!results.isEmpty)
        #expect(results.first?.title == "创造性判断")
        #expect((results.first?.score ?? 0) > 0)
    }

    @Test func semanticSearch_ignoresIndexFiles() throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        let wikiDir = vault.appendingPathComponent("Wiki")
        try FileManager.default.createDirectory(at: wikiDir, withIntermediateDirectories: true)

        try "index content".write(to: wikiDir.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
        try "# 真实页面\n\n正文内容。"
            .write(to: wikiDir.appendingPathComponent("真实页面.md"), atomically: true, encoding: .utf8)

        // "index content" does not appear in "真实页面.md", so results should be empty
        let results = try adapter.semanticSearch(query: "index content")
        #expect(results.isEmpty)
    }

    @Test func semanticSearch_noMatch_returnsEmpty() throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        let wikiDir = vault.appendingPathComponent("Wiki")
        try FileManager.default.createDirectory(at: wikiDir, withIntermediateDirectories: true)

        try "# 创造性判断\n\n三步法。".write(to: wikiDir.appendingPathComponent("创造性判断.md"), atomically: true, encoding: .utf8)

        let results = try adapter.semanticSearch(query: "新颖性")
        #expect(results.isEmpty)
    }

    // MARK: - Rule Retrieval

    @Test func retrieveRules_returnsMatchingCandidates() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        let wikiDir = vault.appendingPathComponent("Wiki")

        // Create module index
        let moduleDir = wikiDir.appendingPathComponent("专利实务")
        try FileManager.default.createDirectory(at: moduleDir, withIntermediateDirectories: true)
        try "- [[创造性判断]]\n- [[新颖性判断]]"
            .write(to: moduleDir.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)

        // Create linked pages
        try "# 创造性判断\n\n三步法判断是否具备创造性。"
            .write(to: wikiDir.appendingPathComponent("创造性判断.md"), atomically: true, encoding: .utf8)
        try "# 新颖性判断\n\n单独对比原则。"
            .write(to: wikiDir.appendingPathComponent("新颖性判断.md"), atomically: true, encoding: .utf8)

        let rules: RuleRetrievalResult = try await adapter.retrieveRules(query: "创造性", module: .patentPractice)

        #expect(!rules.candidates.isEmpty)
        #expect(rules.candidates.count == 1)
        #expect(rules.candidates.first?.title == "创造性判断")
    }

    @Test func retrieveRules_allModules_whenNoModuleSpecified() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        let wikiDir = vault.appendingPathComponent("Wiki")

        // Only create one module's index — the others are empty
        let moduleDir = wikiDir.appendingPathComponent("法律法规")
        try FileManager.default.createDirectory(at: moduleDir, withIntermediateDirectories: true)
        try "- [[专利法第22条]]"
            .write(to: moduleDir.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
        try "# 专利法第22条\n\n新颖性和创造性。"
            .write(to: wikiDir.appendingPathComponent("专利法第22条.md"), atomically: true, encoding: .utf8)

        let rules: RuleRetrievalResult = try await adapter.retrieveRules(query: "新颖性")

        #expect(!rules.candidates.isEmpty)
        #expect(rules.candidates.first?.sourceLevel == 1)  // laws -> sourceLevel 1
    }

    // MARK: - Cross-Reference Parsing

    @Test func readCrossReferences_parsesConsistentAnnotations() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        let wikiDir = vault.appendingPathComponent("Wiki")

        let moduleDir = wikiDir.appendingPathComponent("专利实务")
        try FileManager.default.createDirectory(at: moduleDir, withIntermediateDirectories: true)
        try "- [[测试引用]]"
            .write(to: moduleDir.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)

        try "# 测试引用\n\n关于创造性判断，⟷一致"
            .write(to: wikiDir.appendingPathComponent("测试引用.md"), atomically: true, encoding: .utf8)

        let refs = try await adapter.readCrossReferences()

        #expect(!refs.isEmpty)
        #expect(refs.contains(where: { $0.nature == .consistent }))
    }

    @Test func readCrossReferences_parsesDivergenceAnnotations() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        let wikiDir = vault.appendingPathComponent("Wiki")

        let moduleDir = wikiDir.appendingPathComponent("专利实务")
        try FileManager.default.createDirectory(at: moduleDir, withIntermediateDirectories: true)
        try "- [[争议规则]]"
            .write(to: moduleDir.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)

        try "# 争议规则\n\n不同法院认定不同。⟷分歧（标准不一致）"
            .write(to: wikiDir.appendingPathComponent("争议规则.md"), atomically: true, encoding: .utf8)

        let refs = try await adapter.readCrossReferences()

        #expect(!refs.isEmpty)
        #expect(refs.contains(where: { $0.nature == CrossReferenceNature.divergence }))
    }

    // MARK: - Query Archive

    @Test func archiveQuery_createsFile() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        try await adapter.archiveQuery(query: "什么是创造性", result: "创造性是指与现有技术相比具有实质性特点和进步。")

        let queriesDir = vault.appendingPathComponent("Queries")
        let files = try FileManager.default.contentsOfDirectory(atPath: queriesDir.path)

        #expect(files.count == 1)
        #expect(files.first?.hasPrefix("query-") == true)
        #expect(files.first?.hasSuffix(".md") == true)
    }

    @Test func archiveQuery_contentContainsQueryAndResult() async throws {
        let vault = try createTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        try await adapter.archiveQuery(query: "测试查询", result: "测试结果内容")

        let queriesDir = vault.appendingPathComponent("Queries")
        let files = try FileManager.default.contentsOfDirectory(atPath: queriesDir.path)
        let content = try String(contentsOf: queriesDir.appendingPathComponent(files[0]), encoding: .utf8)

        #expect(content.contains("测试查询"))
        #expect(content.contains("测试结果内容"))
    }
}
