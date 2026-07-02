import Foundation

/// 语义检索命中结果 — 包含 chunk 文本、文档元信息和相似度分数
///
/// 对接 XiaoNuo Agent `@nuo/knowledge` schema 的 embeddings + chunks + documents 三表。
/// 参见 docs/P0-3-semantic-retrieval-design.md 附录 A。
public struct IndexHit: Sendable {

    /// chunk 文本内容（chunks.content）
    public let chunkText: String

    /// 所属文档 ID（documents.id）
    public let documentId: String

    /// 文档标题（documents.title）
    public let title: String

    /// 文档来源（documents.source: wiki / raw / law / guideline / trademark）
    public let source: String

    /// 文档类型（documents.doc_type: law_article / guideline_rule / judgment / concept ...）
    public let docType: String

    /// 模块（documents.module: 专利实务 / 审查指南 / 专利侵权 ...）
    public let module: String?

    /// 余弦相似度分数 0.0-1.0，值越大越相关
    public let score: Double

    /// chunk 标题（chunks.heading），可能为 nil
    public let heading: String?

    public init(
        chunkText: String,
        documentId: String,
        title: String,
        source: String,
        docType: String,
        module: String?,
        score: Double,
        heading: String?
    ) {
        self.chunkText = chunkText
        self.documentId = documentId
        self.title = title
        self.source = source
        self.docType = docType
        self.module = module
        self.score = score
        self.heading = heading
    }
}

/// 语义索引过滤条件 — 按 domain / module / docType 收窄检索范围
public struct IndexFilter: Sendable {

    /// 领域过滤（"patent" / "trademark" / "copyright" / "general_law"）
    public let domain: String?

    /// 模块过滤（["专利实务", "审查指南"]）
    public let modules: Set<String>?

    /// 文档类型过滤（["law_article", "guideline_rule"]）
    public let docTypes: Set<String>?

    public init(domain: String? = nil, modules: Set<String>? = nil, docTypes: Set<String>? = nil) {
        self.domain = domain
        self.modules = modules
        self.docTypes = docTypes
    }

    /// 空过滤器（不过滤，全量检索）
    public static let none = IndexFilter()
}

/// 语义索引协议 — 向量检索统一接口，定义 search 方法和索引元数据
///
/// 实现：
/// - ``SQLiteVectorIndex``（对接 XiaoNuo Agent schema 的生产级索引）
/// - ``InMemoryVectorIndex``（运行时扫描 vault 的降级方案）
public protocol SemanticIndex: Sendable {

    /// 显示名（用于 UI 和日志）
    var displayName: String { get }

    /// 索引是否可用（SQLite 文件存在且含 embeddings / InMemory 已完成扫描）
    var isAvailable: Bool { get async }

    /// 已索引的向量数量
    var vectorCount: Int { get async }

    /// 向量检索（无过滤）
    /// - Parameters:
    ///   - queryEmbedding: query 向量（长度须等于 ``EmbeddingProvider/dimension``）
    ///   - topK: 返回数量上限
    ///   - minScore: 最低相似度阈值（默认 0.3）
    /// - Returns: 按 score 降序排列的命中列表
    func search(
        queryEmbedding: [Float],
        topK: Int,
        minScore: Float
    ) async throws -> [IndexHit]

    /// 向量检索（带过滤）
    func search(
        queryEmbedding: [Float],
        topK: Int,
        minScore: Float,
        filter: IndexFilter?
    ) async throws -> [IndexHit]
}

/// 默认实现：无过滤版本委托给带过滤版本
public extension SemanticIndex {

    func search(
        queryEmbedding: [Float],
        topK: Int,
        minScore: Float = 0.3
    ) async throws -> [IndexHit] {
        try await search(queryEmbedding: queryEmbedding, topK: topK, minScore: minScore, filter: nil)
    }
}
