import Foundation
import Testing

@testable import YunPatCore

/// S2 验证：KeywordEmbedder + InMemoryVectorIndex + RuleEngine 六步管道
struct SemanticRetrievalTests {

    // MARK: - Helpers

    private func createMockVault() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let wikiDir = tmp.appendingPathComponent("Wiki")
        let practiceDir = wikiDir.appendingPathComponent("专利实务")
        try FileManager.default.createDirectory(at: practiceDir, withIntermediateDirectories: true)

        // Concept-Index
        try """
        # 概念索引
        - [[创造性判断]] 创造性 三步法
        - [[新颖性判断]] 新颖性 单独对比
        - [[权利要求撰写]] 权利要求 撰写
        """.write(to: wikiDir.appendingPathComponent("Concept-Index.md"), atomically: true, encoding: .utf8)

        // Wiki 页面
        try "# 创造性判断\n\n三步法是判断创造性的核心方法。确定最接近的现有技术，确定区别技术特征，判断是否显而易见。"
            .write(to: wikiDir.appendingPathComponent("创造性判断.md"), atomically: true, encoding: .utf8)
        try "# 新颖性判断\n\n新颖性判断采用单独对比原则。属于现有技术的不具备新颖性。"
            .write(to: wikiDir.appendingPathComponent("新颖性判断.md"), atomically: true, encoding: .utf8)
        try "# 权利要求撰写\n\n权利要求应当以说明书为依据，清楚、简要地限定要求专利保护的范围。"
            .write(to: wikiDir.appendingPathComponent("权利要求撰写.md"), atomically: true, encoding: .utf8)

        return tmp
    }

    // MARK: - KeywordEmbedder

    @Test func keywordEmbedder_dimension() async throws {
        let embedder = KeywordEmbedder()
        #expect(embedder.dimension == 1024)
        #expect(embedder.modelName == "keyword-mock")
        #expect(await embedder.isReady == true)
    }

    @Test func keywordEmbedder_batchEmbed() async throws {
        let embedder = KeywordEmbedder()
        let texts = ["创造性判断", "新颖性 三步法", "hello world"]
        let vectors = try await embedder.embed(texts)

        #expect(vectors.count == 3)
        for vec in vectors {
            #expect(vec.count == 1024)
            // 非零向量应 L2 归一化（norm ≈ 1）
            let norm = sqrt(vec.map { $0 * $0 }.reduce(0, +))
            #expect(norm > 0.99 && norm < 1.01)
        }
    }

    @Test func keywordEmbedder_deterministic() async throws {
        let embedder = KeywordEmbedder()
        let v1 = try await embedder.embed(["创造性三步法"])
        let v2 = try await embedder.embed(["创造性三步法"])
        #expect(v1[0] == v2[0])  // 相同输入 → 相同输出
    }

    @Test func keywordEmbedder_sharedTermsHighSimilarity() async throws {
        let embedder = KeywordEmbedder()
        let vectors = try await embedder.embed(["创造性 三步法 判断", "创造性 三步法"])
        let sim = cosineSim(vectors[0], vectors[1])
        // 含相同 term 的文本余弦相似度应较高
        #expect(sim > 0.5)
    }

    // MARK: - InMemoryVectorIndex

    @Test func inMemoryIndex_scanAndSearch() async throws {
        let vault = try createMockVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let embedder = KeywordEmbedder()
        let index = InMemoryVectorIndex(vaultPath: vault, embedder: embedder)

        // scan 前不可用
        #expect(await index.isAvailable == false)
        #expect(await index.vectorCount == 0)

        try await index.scan()

        #expect(await index.isAvailable == true)
        #expect(await index.vectorCount > 0)  // 至少 3 个页面被分块

        // 检索
        let queryVec = try await embedder.embed(["创造性 三步法"])[0]
        let hits = try await index.search(queryEmbedding: queryVec, topK: 5, minScore: 0.1)

        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { $0.score >= 0.1 })
        // top1 应涉及"创造性"
        #expect(hits[0].title.contains("创造性") || hits[0].chunkText.contains("创造性"))
    }

    @Test func inMemoryIndex_emptyVault() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let embedder = KeywordEmbedder()
        let index = InMemoryVectorIndex(vaultPath: tmp, embedder: embedder)
        try await index.scan()

        #expect(await index.isAvailable == true)
        #expect(await index.vectorCount == 0)

        let queryVec = try await embedder.embed(["测试"])[0]
        let hits = try await index.search(queryEmbedding: queryVec, topK: 5, minScore: 0.1)
        #expect(hits.isEmpty)
    }

    // MARK: - RuleEngine 完整语义管道

    @Test func ruleEngine_semanticPipeline() async throws {
        let vault = try createMockVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        let engine = RuleEngine(adapter: adapter)

        let facts = StructuredFacts(
            technicalField: "机械装置",
            problem: "如何判断创造性",
            inventionPoints: ["三步法判断创造性"]
        )

        let rules = try await engine.retrieveRules(for: facts)

        // Step 2 Concept-Index 应命中 + Step 3 语义兜底应增强
        #expect(!rules.candidates.isEmpty)
        // 至少有一条涉及"创造性"
        #expect(rules.candidates.contains { $0.title.contains("创造性") || $0.content.contains("创造性") })
    }

    @Test func ruleEngine_backwardCompat_zeroDependency() async throws {
        let vault = try createMockVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let adapter = WikiAdapter(vaultPath: vault)
        // 向后兼容初始化（无 embedder/index）
        let engine = RuleEngine(adapter: adapter)

        let facts = StructuredFacts(
            technicalField: "机械",
            problem: "创造性",
            inventionPoints: ["创造性判断"]
        )

        // 应仍能通过 Concept-Index 命中返回结果
        let rules = try await engine.retrieveRules(for: facts)
        #expect(!rules.candidates.isEmpty)
    }

    // MARK: - Helpers

    private func cosineSim(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).map(*).reduce(0, +)
        let na = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let nb = sqrt(b.map { $0 * $0 }.reduce(0, +))
        return na > 0 && nb > 0 ? dot / (na * nb) : 0
    }
}
