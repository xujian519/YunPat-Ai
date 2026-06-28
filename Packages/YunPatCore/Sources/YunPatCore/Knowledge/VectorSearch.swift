import Foundation

/// 语义检索服务 — 混合 BM25 + 向量（通过 BGE-M3 API）
///
/// 向量检索通过本地 MCP Server `bge-embeddings` 提供。
/// 不可用时降级为简单关键词匹配。
public actor VectorSearch {
    public static let shared = VectorSearch()

    /// 向量化回调（由外部注入，通过 MCP 或本地 BGE 服务）
    public var embedHandler: (@Sendable ([String]) async -> [[Float]]?)?

    private init() {}

    /// 设置 embedding handler（App 启动时调用）
    public func setEmbedHandler(_ handler: @escaping @Sendable ([String]) async -> [[Float]]?) {
        self.embedHandler = handler
    }

    /// 检索与 query 最相似的文本
    /// - Parameters:
    ///   - query: 查询文本
    ///   - candidates: 候选文本列表
    ///   - topK: 返回 topK 结果
    ///   - minScore: 最低相似度阈值（0-1）
    /// - Returns: [(index, score)]
    public func search(query: String, candidates: [String], topK: Int = 5, minScore: Float = 0.3) async -> [(Int, Float)] {
        guard !candidates.isEmpty else { return [] }

        // 尝试向量检索
        if let handler = embedHandler {
            let texts = [query] + candidates
            if let vectors = await handler(texts), vectors.count == texts.count {
                let queryVec = vectors[0]
                let candidateVecs = Array(vectors[1...])
                let scored = candidateVecs.enumerated().map { (i, vec) -> (Int, Float) in
                    (i, Self.cosineSimilarity(queryVec, vec))
                }
                let filtered = scored.filter { $0.1 >= minScore }
                return filtered.sorted { $0.1 > $1.1 }.prefix(topK).map { $0 }
            }
        }

        // 降级：关键词匹配（BM25 简化版）
        return keywordSearch(query: query, candidates: candidates, topK: topK)
    }

    // MARK: - Keyword Fallback (TF 简化)

    private func keywordSearch(query: String, candidates: [String], topK: Int) -> [(Int, Float)] {
        let queryTerms = Set(query.lowercased().split(separator: " ").map(String.init))
        guard !queryTerms.isEmpty else { return [] }

        let scored: [(Int, Float)] = candidates.enumerated().map { (i, text) in
            let lower = text.lowercased()
            let matchCount = queryTerms.filter { lower.contains($0) }.count
            let score = Float(matchCount) / Float(queryTerms.count)
            return (i, score)
        }
        return scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(topK).map { $0 }
    }

    // MARK: - Cosine Similarity

    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }
}
