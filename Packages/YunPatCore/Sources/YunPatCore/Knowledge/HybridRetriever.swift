import Foundation

// MARK: - Search Source

/// 检索来源 — 标识结果由哪个检索通道产生
public enum RetrievalSource: String, Sendable, CaseIterable {
    case fts
    case vector
    case graph
    case hybrid
}

// MARK: - Fusion Config

/// RRF 融合配置
public struct FusionConfig: Sendable {
    /// FTS 全文检索权重 (0–1)
    public var ftsWeight: Double
    /// 向量语义检索权重 (0–1)
    public var vectorWeight: Double
    /// 知识图谱增强权重 (0–1)，预留扩展
    public var graphBoost: Double
    /// RRF 平滑常数 k，避免除零并抑制极端排名差异
    public var rrfK: Int

    public init(
        ftsWeight: Double = 0.4,
        vectorWeight: Double = 0.5,
        graphBoost: Double = 0.1,
        rrfK: Int = 60
    ) {
        self.ftsWeight = ftsWeight
        self.vectorWeight = vectorWeight
        self.graphBoost = graphBoost
        self.rrfK = rrfK
    }
}

// MARK: - Ranked Result

/// 融合后的排序结果
public struct RankedResult: Sendable {
    public let documentId: String
    public let content: String
    public let source: RetrievalSource
    public let score: Double
    public let rank: Int

    public init(
        documentId: String,
        content: String,
        source: RetrievalSource,
        score: Double,
        rank: Int
    ) {
        self.documentId = documentId
        self.content = content
        self.source = source
        self.score = score
        self.rank = rank
    }
}

// MARK: - Hybrid Retriever

/// 混合检索器 — FTS5 全文 + 向量语义 + RRF 融合排序
///
/// 通过 Reciprocal Rank Fusion 将多个检索通道的结果融合为单一排序：
///   score(d) = Σ wₛ × 1/(k + rankₛ(d))
/// 其中 s ∈ {fts, vector}，k = rrfK，wₛ 为各通道权重。
public actor HybridRetriever {
    public static let shared: HybridRetriever = HybridRetriever()
    private init() {}

    // MARK: - Retrieve

    /// 执行混合检索与 RRF 融合
    /// - Parameters:
    ///   - query: 用户查询（预留，可用于相关性判断）
    ///   - ftsResults: FTS 全文检索结果，元素为 (documentId, rawScore)，已按分数降序排列
    ///   - vectorResults: 向量语义检索结果，元素为 (documentId, rawScore)，已按分数降序排列
    ///   - config: 融合配置，nil 则使用默认值
    /// - Returns: RRF 融合并去重后的排序结果
    public func retrieve(
        query: String,
        ftsResults: [(String, Double)],
        vectorResults: [(String, Double)],
        config: FusionConfig? = nil
    ) async -> [RankedResult] {
        let cfg = config ?? FusionConfig()

        // 收集所有文档的 RRF 贡献，按 documentId 聚合
        var scoreMap: [String: Double] = [String: Double]()
        // FTS 通道：rank 从 1 开始
        for (index, (docId, _)) in ftsResults.enumerated() {
            let rank = index + 1
            let rrf = cfg.ftsWeight / (Double(cfg.rrfK) + Double(rank))
            scoreMap[docId, default: 0] += rrf
        }

        // Vector 通道
        for (index, (docId, _)) in vectorResults.enumerated() {
            let rank = index + 1
            let rrf = cfg.vectorWeight / (Double(cfg.rrfK) + Double(rank))
            scoreMap[docId, default: 0] += rrf
        }

        guard !scoreMap.isEmpty else { return [] }

        // 构建结果并排序
        var sorted =
            scoreMap
            .map { (docId: $0.key, score: $0.value) }
            .sorted { $0.score > $1.score }

        // 归一化到 [0, 1]
        if let maxScore = sorted.first?.score, maxScore > 0 {
            for index in sorted.indices {
                sorted[index].score /= maxScore
            }
        }

        // 组装 RankedResult，去重已由 scoreMap 保证
        return sorted.enumerated().map { (index, entry) in
            let rank = index + 1

            // 推断主要来源
            let source: RetrievalSource = {
                let inFts = ftsResults.contains(where: { $0.0 == entry.docId })
                let inVec = vectorResults.contains(where: { $0.0 == entry.docId })
                if inFts && inVec { return .hybrid }
                if inFts { return .fts }
                return .vector
            }()

            return RankedResult(
                documentId: entry.docId,
                content: "",
                source: source,
                score: entry.score,
                rank: rank
            )
        }
    }
}
