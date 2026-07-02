import Foundation

/// 语义检索服务 — 混合 BM25 + 向量（BGE-M3），不可用时降级为关键词匹配
///
/// 向量检索通过本地 MCP Server `bge-embeddings` 提供。
/// 不可用时降级为简单关键词匹配。
public actor VectorSearch {
    public static let shared: VectorSearch = VectorSearch()

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
    public func search(
        query: String, candidates: [String], topK: Int = 5, minScore: Float = 0.3
    ) async -> [(Int, Float)] {
        guard !candidates.isEmpty else { return [] }

        // 尝试向量检索
        if let handler = embedHandler {
            let texts: [String] = [query] + candidates
            if let vectors = await handler(texts), vectors.count == texts.count {
                let queryVec: [Float] = vectors[0]
                let candidateVecs: [[Float]] = Array(vectors[1...])
                let scored: [(Int, Float)] = candidateVecs.enumerated().map { (index, vec) -> (Int, Float) in
                    (index, Self.cosineSimilarity(queryVec, vec))
                }
                let filtered: [(Int, Float)] = scored.filter { $0.1 >= minScore }
                return filtered.sorted { $0.1 > $1.1 }.prefix(topK).map { $0 }
            }
        }

        // 降级：关键词匹配（BM25 简化版）
        return keywordSearch(query: query, candidates: candidates, topK: topK)
    }

    // MARK: - Keyword Fallback (TF 简化)

    private func keywordSearch(query: String, candidates: [String], topK: Int) -> [(Int, Float)] {
        let queryTerms: Set<String> = Set(query.lowercased().split(separator: " ").map(String.init))
        guard !queryTerms.isEmpty else { return [] }

        let scored: [(Int, Float)] = candidates.enumerated().map { (index, text) in
            let lower: String = text.lowercased()
            let matchCount: Int = queryTerms.filter { lower.contains($0) }.count
            let score: Float = Float(matchCount) / Float(queryTerms.count)
            return (index, score)
        }
        return scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(topK).map { $0 }
    }

    // MARK: - Cosine Similarity

    public static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        let dot: Float = zip(lhs, rhs).map(*).reduce(0, +)
        let normA: Float = sqrt(lhs.map { $0 * $0 }.reduce(0, +))
        let normB: Float = sqrt(rhs.map { $0 * $0 }.reduce(0, +))
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }
}
