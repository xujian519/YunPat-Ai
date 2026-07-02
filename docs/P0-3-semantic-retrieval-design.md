---
status: 草案 (2026-07-02)
范围: YunPatCore/Knowledge + App/Views/Settings + YunPatNetworking/Providers
关联: docs/superpowers/specs/2026-06-27-yunpat-ai-design.md §3 §12, docs/superpowers/plans/2026-06-28-yunpat-ai-plan7-flesh-out-full.md Task P0-3
前置条件: P0-1 流式聊天 ✅, P0-2 会话记忆 ✅, P0-4 Token 预算 ✅ (均已完成)
---

# P0-3 知识库语义化检索 — 设计文档

## 一、目标与非目标

### 目标
1. **PatentLoop Step 2「获取规则」从空壳变为可用** — 输入技术事实，返回相关法条/审查指南/判例
2. **knowledge_search 工具产出真实语义检索结果** — 替换当前 `contains` 子串匹配占位
3. **本地 MLX embedding**（bge-m3-mlx-8bit，1024 维）— 离线、低延迟、无 API 依赖
4. **直接对接 XiaoNuo Agent 知识库 schema** — 用户的法律+专利知识库完成后即插即用
5. **用户可配置自己的 vault 或索引路径** — 设置面板手动指定

### 非目标（本轮不做）
- FTS5 全文检索通道（YunPat-Ai 端）— 本轮只做向量通道，FTS 留待 v1.1
- 知识图谱（kg_nodes/kg_edges）扩展 — 留待 v1.1
- IVF 加速索引 — Swift 端先做全量扫描 topK，性能够用前不引入 IVF
- 自动索引构建（indexer）— 索引由 XiaoNuo Agent 的 `@nuo/knowledge` 包构建，YunPat-Ai 只读

---

## 二、现状分析

### 2.1 YunPat-Ai 现状（待改造）

| 文件 | 现状 | 问题 |
|---|---|---|
| `Knowledge/WikiAdapter.swift:74` `retrieveRules` | `contains(query.lowercased())` 子串匹配 | 非语义，召回率低 |
| `Knowledge/WikiAdapter.swift:55` `semanticSearch` | 同样是 `contains` | 名不副实 |
| `Knowledge/RuleEngine.swift` | 空壳 | PatentLoop Step 2 无产出 |
| `Knowledge/VectorSearch.swift` | **已有 `embedHandler` 注入点**，向量+关键词降级 | 设计良好，可复用 |
| `Tools/TypedKnowledgeSearchTool.swift` | 已有 `searcher` 闭包注入 | 适配层就绪 |
| `Knowledge/WikiTypes.swift` | 类型完善（`RuleCandidate`/`ApplicableRules`/`RuleConflict`/`EvidenceLink`） | 可直接复用 |
| `App/Views/Settings/KnowledgeSettingsView.swift` | vault 路径选择（硬编码宝宸库） | 需泛化 + 增加 embedding/索引配置 |
| `Networking/Providers/OMLXBackend.swift` | 子进程调 `python3 -m mlx_lm.generate` | 只有 chat，无 embedding；非原生 MLX |

### 2.2 XiaoNuo Agent 知识库 schema（对接目标）

`@nuo/knowledge` 包的 `createSchema` 定义了以下表，YunPat-Ai **只读消费**：

```sql
-- 文档元数据
documents(id, source, doc_type, domain, title, file_path, module, priority,
          level, publish_date, case_number, court, decision_number,
          article_number, content_hash, indexed_at, char_count, chunk_count)

-- 文档分块
chunks(id, document_id, chunk_index, chunk_type, heading, content, char_count)

-- ★ 向量嵌入表（本轮核心对接目标）
embeddings(
    id          INTEGER PK AUTOINCREMENT,
    chunk_id    INTEGER NOT NULL REFERENCES chunks(id),
    document_id TEXT NOT NULL REFERENCES documents(id),
    vector      BLOB NOT NULL,          -- Float32Array, 1024 dims
    model       TEXT DEFAULT 'bge-m3',
    dim         INTEGER DEFAULT 1024,
    norm        REAL DEFAULT 0.0,
    indexed_at  TEXT NOT NULL
)

-- 辅助表（本轮不读）
docs_fts, kg_nodes, kg_edges, kg_nodes_fts, ivf_index, index_meta, version_history
```

**关键参数**：
- 维度：**1024**（bge-m3）
- 向量格式：**Float32Array → BLOB**（little-endian，连续内存）
- 模型：`bge-m3`
- 余弦相似度：`dot(q,d) / (||q|| × ||d||)`，预存 `norm` 列优化

### 2.3 混合检索基线（XiaoNuo Agent 已实现，供参考）

XiaoNuo 的 `hybrid-retriever.ts` 用 Reciprocal Rank Fusion 融合三路：
- FTS（权重 0.4）
- Vector（权重 0.4）
- Graph 扩展（权重 0.2）

YunPat-Ai 本轮只实现 **Vector 通道**（权重 1.0），FTS/Graph 留待后续。

---

## 三、架构设计

### 3.1 三层抽象（可插拔）

```
┌──────────────────────────────────────────────────────────┐
│  消费层：PatentLoop Step 2 / knowledge_search Tool         │
│  （消费 ApplicableRules / [KnowledgeSearchResultItem]）     │
└────────────────────────┬─────────────────────────────────┘
                         │
┌────────────────────────▼─────────────────────────────────┐
│  管道层：RuleEngine（actor）— 六步检索管道                   │
│  概念提取 → Concept-Index 反查 → 语义兜底 → 全文读取        │
│           → 跨源标注解析 → 组装 ApplicableRules              │
│  依赖注入: EmbeddingProvider + SemanticIndex + WikiAdapter  │
└──┬──────────────────────┬───────────────────┬────────────┘
   │                      │                   │
┌──▼─────────────┐  ┌─────▼──────────┐  ┌────▼──────────────┐
│ EmbeddingProvider│  │ SemanticIndex  │  │ WikiAdapter       │
│ (协议)           │  │ (协议)          │  │ (文件直读，已有)   │
├─────────────────┤  ├────────────────┤  │ 改造: retrieveRules│
│ MLXEmbedding    │  │ SQLiteVector   │  │ 委托给 RuleEngine  │
│ Provider        │  │ Index          │  └───────────────────┘
│ (bge-m3-mlx-8bit│  │ (对接 XiaoNuo  │
│  原生 mlx-swift) │  │  schema)       │
│                 │  │ InMemoryVector │
│ KeywordEmbedder │  │ Index (降级)    │
│ (mock，开发用)   │  │                │
└─────────────────┘  └────────────────┘
```

### 3.2 核心设计原则

1. **协议先行** — `EmbeddingProvider` 和 `SemanticIndex` 是协议，实现可替换
2. **只读消费** — YunPat-Ai 不构建索引，只读取 XiaoNuo Agent 产出的 SQLite
3. **优雅降级** — MLX 不可用 → 关键词；SQLite 索引不存在 → InMemory 扫描；全失败 → 空结果不崩溃
4. **延迟初始化** — MLX 模型首次检索时加载（~3s），后续复用；App 启动不阻塞
5. **配置驱动** — 所有路径通过设置面板配置，UserDefaults 持久化

---

## 四、协议定义（S1 产出）

### 4.1 EmbeddingProvider

```swift
// Knowledge/EmbeddingProvider.swift

/// 文本向量化提供者协议
/// 实现：MLXEmbeddingProvider（主力）、KeywordEmbedder（开发 mock）
public protocol EmbeddingProvider: Sendable {
    /// 向量维度（bge-m3 = 1024）
    var dimension: Int { get }
    /// 模型标识（用于与索引的 model 列校验）
    var modelName: String { get }
    /// 是否已就绪可调用（MLX 需异步加载）
    var isReady: Bool { get }

    /// 批量向量化
    /// - Parameter texts: 待编码文本数组
    /// - Returns: 与 texts 等长的向量数组，每个向量长度 == dimension
    func embed(_ texts: [String]) async throws -> [[Float]]
}
```

### 4.2 SemanticIndex

```swift
// Knowledge/SemanticIndex.swift

/// 语义检索命中
public struct IndexHit: Sendable {
    /// chunk 文本内容（从 chunks.content 读取）
    public let chunkText: String
    /// 所属文档 ID（documents.id）
    public let documentId: String
    /// 文档标题（documents.title）
    public let title: String
    /// 文档来源（documents.source: wiki/raw/law/guideline）
    public let source: String
    /// 文档类型（documents.doc_type: law_article/guideline_rule/judgment...）
    public let docType: String
    /// 模块（documents.module: 专利实务/审查指南/专利侵权...）
    public let module: String?
    /// 余弦相似度分数 0.0-1.0
    public let score: Double
    /// chunk 标题（chunks.heading）
    public let heading: String?
}

/// 语义索引协议
/// 实现：SQLiteVectorIndex（对接 XiaoNuo schema）、InMemoryVectorIndex（降级）
public protocol SemanticIndex: Sendable {
    /// 显示名（用于 UI 和日志）
    var displayName: String { get }
    /// 索引是否可用（SQLite 文件存在 / InMemory 已扫描）
    var isAvailable: Bool { get }
    /// 已索引的向量数量
    var vectorCount: Int { get }

    /// 向量检索
    /// - Parameters:
    ///   - queryEmbedding: query 向量（长度须 == dimension）
    ///   - topK: 返回数量上限
    ///   - minScore: 最低相似度阈值（默认 0.3）
    /// - Returns: 按 score 降序排列的命中列表
    func search(
        queryEmbedding: [Float],
        topK: Int,
        minScore: Float
    ) async throws -> [IndexHit]

    /// 可选：按 domain/module 过滤（优化检索精度）
    func search(
        queryEmbedding: [Float],
        topK: Int,
        minScore: Float,
        filter: IndexFilter?
    ) async throws -> [IndexHit]
}

/// 索引过滤条件
public struct IndexFilter: Sendable {
    public let domain: String?       // "patent" / "trademark"
    public let modules: Set<String>? // ["专利实务", "审查指南"]
    public let docTypes: Set<String>?// ["law_article", "guideline_rule"]
    public init(domain: String? = nil, modules: Set<String>? = nil, docTypes: Set<String>? = nil) {
        self.domain = domain; self.modules = modules; self.docTypes = docTypes
    }
}
```

---

## 五、实现细节

### 5.1 MLXEmbeddingProvider（S3 — 原生 mlx-swift 集成）

#### 5.1.1 SPM 依赖

```swift
// Packages/YunPatCore/Package.swift 新增
dependencies: [
    .package(path: "../YunPatNetworking"),
    .package(url: "https://github.com/ml-explore/mlx-swift-extras", from: "0.5.0"),
],
targets: [
    .target(name: "YunPatCore", dependencies: [
        .product(name: "YunPatNetworking", package: "YunPatNetworking"),
        .product(name: "MLXLMCommon", package: "mlx-swift-extras"),
        .product(name: "MLXEmbedding", package: "mlx-swift-extras"),
    ]),
]
```

> **注**：`mlx-swift-extras` 的 `MLXEmbedding` 模块支持加载 sentence-transformer 格式的 embedding 模型。bge-m3 的 MLX 量化版 `mlx-community/bge-m3-mlx-8bit` 兼容此格式。若 extras 暂不支持，回退用 `mlx-swift` 核心 + 手动 mean-pooling 实现（bge-m3 是 BERT 架构，取 last_hidden_state 均值池化）。

#### 5.1.2 实现

```swift
// Knowledge/MLXEmbeddingProvider.swift

/// 本地 MLX embedding 提供者 — bge-m3-mlx-8bit
/// 首次调用时加载模型（~3s），后续复用
public actor MLXEmbeddingProvider: EmbeddingProvider {
    public let dimension: Int = 1024
    public let modelName: String = "bge-m3-mlx-8bit"
    public private(set) var isReady: Bool = false

    private let modelPath: URL           // ~/.yunpat/models/bge-m3-mlx-8bit/
    private var model: AnyObject?        // MLXEmbedding.Model（actor 内持有）
    private var tokenizer: AnyObject?    // MLXEmbedding.Tokenizer

    public init(modelPath: URL) {
        self.modelPath = modelPath
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        if !isReady { try await loadModel() }
        // 1. tokenize（bge-m3 用 XLM-RoBERTa tokenizer，max_length=512）
        // 2. 前向推理 → last_hidden_state [batch, seq_len, 1024]
        // 3. mean pooling（attention_mask 加权）→ [batch, 1024]
        // 4. L2 normalize
        // 返回 [[Float]] 每个内层数组长度 1024
        fatalError("S3 阶段实现")
    }

    private func loadModel() async throws {
        // 加载 mlx-community/bge-m3-mlx-8bit 的 weights + config + tokenizer
        // 设置 isReady = true
    }
}
```

#### 5.1.3 模型下载

App 首次配置时，提供「下载 bge-m3-mlx-8bit」按钮：
- 从 HuggingFace `mlx-community/bge-m3-mlx-8bit` 下载（~600MB）
- 存储到 `~/.yunpat/models/bge-m3-mlx-8bit/`
- 复用 `OMLXBackend.downloadModel` 的下载基础设施

### 5.2 KeywordEmbedder（S2 — 开发 mock，零依赖）

```swift
// Knowledge/KeywordEmbedder.swift

/// 开发用 mock embedder — 不生成真实向量
/// 产生基于词频的伪向量，仅用于验证 RuleEngine 管道
/// 生成 1024 维稀疏向量：对每个 query term hash 到一个维度置 1
public struct KeywordEmbedder: EmbeddingProvider {
    public let dimension: Int = 1024
    public let modelName: String = "keyword-mock"
    public let isReady: Bool = true

    public init() {}

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map { text in
            var vec = [Float](repeating: 0, count: 1024)
            for term in text.lowercased().split(separator: " ") {
                let idx = abs(term.hashValue % 1024)
                vec[idx] = 1.0
            }
            // L2 normalize
            let norm = sqrt(vec.map { $0 * $0 }.reduce(0, +))
            return norm > 0 ? vec.map { $0 / norm } : vec
        }
    }
}
```

### 5.3 SQLiteVectorIndex（S4 — 对接 XiaoNuo schema）

```swift
// Knowledge/SQLiteVectorIndex.swift

/// 对接 XiaoNuo Agent @nuo/knowledge schema 的向量索引
/// 只读消费 embeddings + chunks + documents 三表
public final class SQLiteVectorIndex: SemanticIndex, @unchecked Sendable {
    public let displayName: String
    public private(set) var isAvailable: Bool = false
    public private(set) var vectorCount: Int = 0

    private let dbPath: URL
    private var db: OpaquePointer?
    private let dimension: Int = 1024

    public init(dbPath: URL) throws {
        self.dbPath = dbPath
        self.displayName = "SQLite: \(dbPath.lastPathComponent)"
        try open()
    }

    private func open() throws {
        // sqlite3_open_v2(dbPath, SQLITE_OPEN_READONLY)
        // 检查 embeddings 表存在
        // SELECT COUNT(*) FROM embeddings → vectorCount
        // isAvailable = vectorCount > 0
    }

    public func search(
        queryEmbedding: [Float],
        topK: Int = 10,
        minScore: Float = 0.3
    ) async throws -> [IndexHit] {
        try await search(queryEmbedding: queryEmbedding, topK: topK, minScore: minScore, filter: nil)
    }

    public func search(
        queryEmbedding: [Float],
        topK: Int,
        minScore: Float,
        filter: IndexFilter?
    ) async throws -> [IndexHit] {
        guard isAvailable, queryEmbedding.count == dimension else { return [] }

        // 全量扫描 + topK 堆（性能够用前不引入 IVF）
        // SQL（无过滤）:
        //   SELECT e.chunk_id, e.document_id, e.vector, e.norm,
        //          c.content, c.heading,
        //          d.title, d.source, d.doc_type, d.module
        //   FROM embeddings e
        //   JOIN chunks c ON e.chunk_id = c.id
        //   JOIN documents d ON e.document_id = d.id
        //   [WHERE d.domain = ? AND d.module IN (?...)]
        //
        // Swift 端逐行:
        //   1. 解码 vector BLOB → [Float]（withUnsafeBytes）
        //   2. 计算 cos = dot(q, d) / (||q|| × e.norm)
        //   3. cos >= minScore → 加入 min-heap（容量 topK）
        //   4. 返回排序结果
        fatalError("S4 阶段实现")
    }

    /// BLOB → [Float] 解码（核心性能路径）
    private func decodeVector(_ blob: Data) -> [Float] {
        blob.withUnsafeBytes { ptr in
            let floatPtr = ptr.bindMemory(to: Float.self)
            return Array(floatPtr)  // 1024 个 Float
        }
    }
}
```

**性能预估**（全量扫描，Apple Silicon）：
- 10K 向量 × 1024 维：~5ms（SIMD 加速的 dot product）
- 50K 向量：~25ms
- 100K 向量：~50ms（此时考虑引入 IVF）

Swift 端 dot product 可用 `vDSP.dot`（Accelerate 框架）加速，无需额外依赖。

### 5.4 InMemoryVectorIndex（S2 — 降级 / 首次使用）

```swift
// Knowledge/InMemoryVectorIndex.swift

/// 内存向量索引 — 无 SQLite 时的降级方案
/// 运行时扫描 vault 的 Wiki/*.md，用 EmbeddingProvider 现场编码
/// 适合：首次使用、用户自定义小 vault、单元测试
public actor InMemoryVectorIndex: SemanticIndex {
    public let displayName: String = "InMemory (runtime scan)"
    public private(set) var isAvailable: Bool = false
    public private(set) var vectorCount: Int = 0

    private let vaultPath: URL
    private let embedder: EmbeddingProvider
    private var entries: [(text: String, meta: IndexHit, vector: [Float])] = []

    public init(vaultPath: URL, embedder: EmbeddingProvider) {
        self.vaultPath = vaultPath
        self.embedder = embedder
    }

    /// 扫描 vault，构建内存索引（首次调用 search 前触发）
    public func scan() async throws {
        // 遍历 Wiki/**/*.md，每个文件按段落分块（双换行分割）
        // 批量 embed（batchSize=32），存入 entries
        // isAvailable = true
    }

    public func search(queryEmbedding: [Float], topK: Int, minScore: Float) async throws -> [IndexHit] {
        if !isAvailable { try await scan() }
        // 逐条计算余弦相似度，topK 排序
        // 复用 VectorSearch.cosineSimilarity
    }
}
```

### 5.5 RuleEngine 六步管道（S2 — 重构现有空壳）

```swift
// Knowledge/RuleEngine.swift （重构）

/// 专利规则检索引擎 — PatentLoop Step 2 的核心
/// 依赖注入：EmbeddingProvider + SemanticIndex + WikiAdapter
public actor RuleEngine {
    private let wiki: WikiAdapter
    private let embedder: EmbeddingProvider
    private let index: SemanticIndex

    public init(wiki: WikiAdapter, embedder: EmbeddingProvider, index: SemanticIndex) {
        self.wiki = wiki
        self.embedder = embedder
        self.index = index
    }

    /// PatentLoop Step 2 入口
    public func retrieveRules(for facts: StructuredFacts, topK: Int = 10) async throws -> ApplicableRules {
        // Step 1: 概念提取（从 inventionPoints + problem 提取法律概念关键词）
        let concepts = extractLegalConcepts(from: facts)

        // Step 2: Concept-Index.md 反查（精确命中，零延迟）
        var wikiHits = try await wiki.lookupConcepts(concepts)

        // Step 3: 语义兜底（未命中或不足 topK → 向量检索）
        if wikiHits.count < topK {
            let query = buildSemanticQuery(facts: facts, concepts: concepts)
            let qVec = try await embedder.embed([query])
            let filter = IndexFilter(domain: "patent")
            let semHits = try await index.search(
                queryEmbedding: qVec[0], topK: topK - wikiHits.count,
                minScore: 0.3, filter: filter
            )
            wikiHits.merge(semanticHits: semHits)  // 去重
        }

        // Step 4: 全文读取（命中的 wikilink/documentId → 读取完整内容）
        let pages = try await wiki.readPages(wikiHits.wikilinks)

        // Step 5: 跨源标注解析（⟷一致 / ⟷分歧）
        let crossRefs = try await wiki.readCrossReferences(for: concepts)
        let conflicts = resolveConflicts(crossRefs)

        // Step 6: 组装 ApplicableRules
        return assemble(candidates: pages + wikiHits.toCandidates(),
                        conflicts: conflicts,
                        constraintSummary: buildConstraintSummary(pages))
    }

    /// 概念提取（轻量规则，非 LLM）
    private func extractLegalConcepts(from facts: StructuredFacts) -> [String] {
        // 从 inventionPoints + problem 提取：
        // - 法律术语词典命中（创造性/新颖性/实用性/充分公开/清楚/...）
        // - 法条编号模式（专利法第X条/第X条第X款/A22.3）
        // - IPC 分类号模式（G06F/H04L/...）
    }

    /// 语义查询构造
    private func buildSemanticQuery(facts: StructuredFacts, concepts: [String]) -> String {
        [facts.technicalField, facts.problem, facts.inventionPoints.joined(separator: " ")]
            .filter { !$0.isEmpty }
            .joined(separator: " ") + " " + concepts.joined(separator: " ")
    }
}
```

---

## 六、设置面板设计（S5）

### 6.1 KnowledgeSettingsView 改造

```
┌─ 知识库 ──────────────────────────────────────────┐
│                                                   │
│ Section 1: Vault 配置                              │
│ ┌───────────────────────────────────────────────┐ │
│ │ Vault 路径: [________________________] [浏览]  │ │
│ │ 状态: ✅ 有效（含 AGENTS.md + Wiki/）          │ │
│ │ [验证]                                         │ │
│ └───────────────────────────────────────────────┘ │
│                                                   │
│ Section 2: 语义检索（可选，提升检索精度）            │
│ ┌───────────────────────────────────────────────┐ │
│ │ ○ 禁用  ○ 关键词模式  ● 语义模式(MLX)          │ │
│ │                                                │ │
│ │ Embedding 模型:                                │ │
│ │ [~/.yunpat/models/bge-m3-mlx-8bit] [浏览]     │ │
│ │ [下载 bge-m3-mlx-8bit] (首次使用)              │ │
│ │ 状态: ✅ 已加载 / ⏳ 下载中(45%) / ❌ 未配置    │ │
│ │                                                │ │
│ │ 语义索引文件:                                  │ │
│ │ [/path/to/knowledge.db] [浏览]                │ │
│ │ 状态: ✅ 12,847 条向量 / ❌ 文件不存在         │ │
│ │ [使用 InMemory 扫描（首次慢，无需索引文件）]    │ │
│ └───────────────────────────────────────────────┘ │
│                                                   │
│ Section 3: 测试检索                                │
│ ┌───────────────────────────────────────────────┐ │
│ │ 查询: [创造性三步法___________________] [检索]  │ │
│ │                                                │ │
│ │ 结果 (8 条，耗时 23ms):                        │ │
│ │  [1] ● 0.87 [law_article] 专利法第22条第3款   │ │
│ │      来源: law | 模块: 法律法规                │ │
│ │  [2] ● 0.82 [guideline_rule] 创造性判断...     │ │
│ │      来源: guideline | 模块: 审查指南          │ │
│ │  ...                                           │ │
│ └───────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────┘
```

### 6.2 配置持久化

```swift
// UserDefaults keys（路径非敏感，不用 Keychain）
enum KnowledgeConfig {
    static let vaultPath = "yunpat.knowledge.vaultPath"
    static let retrievalMode = "yunpat.knowledge.retrievalMode"  // "disabled"/"keyword"/"semantic"
    static let embeddingModelPath = "yunpat.knowledge.embeddingModelPath"
    static let semanticIndexPath = "yunpat.knowledge.semanticIndexPath"
}
```

### 6.3 检索模式三档

| 模式 | embedder | index | 适用场景 |
|---|---|---|---|
| `disabled` | 无 | 无 | 纯聊天，不检索 |
| `keyword` | KeywordEmbedder | InMemoryVectorIndex | 零配置开箱即用 |
| `semantic` | MLXEmbeddingProvider | SQLiteVectorIndex | 生产使用（需配置模型+索引） |

---

## 七、接入 PatentLoop Step 2（S5）

### 7.1 依赖注入链

```
App 启动
  → 读 UserDefaults 配置
  → 构建 EmbeddingProvider（按 retrievalMode）
  → 构建 SemanticIndex（按 semanticIndexPath 是否存在）
  → 构建 RuleEngine(wiki, embedder, index)
  → 注入 PatentLoopEngine
  → PatentLoopEngine.run() Step 2 调用 ruleEngine.retrieveRules(for: facts)
```

### 7.2 PatentLoopEngine 改造点

```swift
// PatentLoopEngine 新增依赖
public actor PatentLoopEngine: LoopEngine {
    private let innerLoop: AgentLoopEngine
    private let ruleEngine: RuleEngine?  // 新增，可选（未配置时 Step 2 跳过）

    // Step 2 实现
    private func step2_retrieveRules(facts: StructuredFacts) async throws -> ApplicableRules {
        guard let ruleEngine else {
            return ApplicableRules()  // 未配置 → 空规则，不阻塞流程
        }
        return try await ruleEngine.retrieveRules(for: facts)
    }
}
```

---

## 八、降级策略（零配置也能用）

```
用户未配置任何东西
  → retrievalMode = "keyword"（默认）
  → KeywordEmbedder + InMemoryVectorIndex(vaultPath)
  → InMemory 扫描 Wiki/*.md 现场编码（慢但可用）
  → RuleEngine 正常工作，只是召回率低

用户配置了 vault 但没 MLX 模型
  → 同上

用户配置了 vault + 下载了 MLX 模型
  → retrievalMode = "semantic"
  → MLXEmbeddingProvider + InMemoryVectorIndex（用真实 MLX 向量）
  → 召回率显著提升

用户配置了 vault + MLX 模型 + XiaoNuo 索引文件
  → retrievalMode = "semantic"
  → MLXEmbeddingProvider + SQLiteVectorIndex（生产级）
  → 毫秒级检索，召回率最佳
```

---

## 九、实施计划

| 阶段 | 内容 | 产出 | 验证标准 | 预估工时 |
|---|---|---|---|---|
| **S1** | 协议定义 + 类型（`EmbeddingProvider`/`SemanticIndex`/`IndexHit`/`IndexFilter`）+ RuleEngine 骨架 | 可编译，现有测试不破 | `swift build` ✅ + `swift test t0` ✅ | 2h |
| **S2** | `KeywordEmbedder` + `InMemoryVectorIndex` + RuleEngine 六步接通 + WikiAdapter.lookupConcepts 实现 | 零依赖可跑 | 单元测试：输入"创造性"→ 返回相关页面 | 4h |
| **S3** | mlx-swift-extras SPM 集成 + `MLXEmbeddingProvider`（bge-m3-mlx-8bit 加载/推理/pooling）+ 模型下载 UI | 真实语义向量 | 测试：MLX 向量 vs 关键词向量，top1 相关度更高 | 8h |
| **S4** | `SQLiteVectorIndex`（对接 XiaoNuo embeddings/chunks/documents schema）+ BLOB 解码 + Accelerate 加速 dot product | 生产级检索 | 用 XiaoNuo knowledge.db 测试：topK < 100ms | 6h |
| **S5** | KnowledgeSettingsView 改造（三档模式 + 测试检索 UI）+ PatentLoopEngine 注入 + knowledge_search Tool 接通 + 端到端集成测试 | 用户可用 | 端到端：设置路径→检索→注入 PatentLoop | 6h |

**总计预估：~26h（约 3-4 个工作日）**

每个阶段结束运行验证 + commit。S3/S4 如遇 mlx-swift 集成阻力，可先用 S2 的关键词模式过渡，不阻塞 S5。

---

## 十、测试计划

### 10.1 单元测试（每个阶段）

```swift
// Tests/EmbeddingProviderTests.swift
- testKeywordEmbedderDimension      // 维度 == 1024
- testKeywordEmbedderNormalize      // L2 norm == 1
- testMLXEmbedderBasicEmbedding     // [S3] 真实模型加载 + 向量长度
- testMLXEmbedderConsistency        // [S3] 相同输入 → 相同输出

// Tests/SemanticIndexTests.swift
- testInMemoryIndexScan             // 扫描 mock vault
- testInMemoryIndexSearch           // topK 排序正确
- testSQLiteIndexOpen               // [S4] 打开 XiaoNuo schema 数据库
- testSQLiteIndexSearch             // [S4] 向量检索 + BLOB 解码

// Tests/RuleEngineTests.swift（扩展现有）
- testRetrieveRulesKeywordFallback  // 关键词降级
- testRetrieveRulesSemanticBoost    // 语义兜底提升召回
- testConceptExtraction             // 法条编号/术语提取
```

### 10.2 集成测试（S5）

```
端到端场景：
1. 配置 vault = 小型测试 vault（10 个 wiki 页面）
2. 检索模式 = keyword
3. 输入 UserRequest("撰写一种机械装置的权利要求，涉及创造性判断")
4. 验证：PatentLoop Step 2 返回 ApplicableRules 非空
5. 验证：至少 1 条 candidate 涉及"创造性"或"专利法第22条"
```

### 10.3 性能基准（S4 后）

```
基准：XiaoNuo Agent knowledge.db（~13K 向量）
- 首次检索延迟（含 MLX query embedding）：< 500ms
- 后续检索延迟（MLX 已加载）：< 100ms
- 内存占用增量：< 50MB
```

---

## 十一、风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| mlx-swift-extras 不支持 bge-m3 embedding | 中 | S3 阻塞 | 回退：手动实现 BERT mean-pooling（mlx-swift 核心 API），或临时用子进程 `python3 -m mlx_lm` |
| XiaoNuo 索引 schema 变更 | 低 | S4 检索失败 | 版本校验（读 index_meta 表），不匹配时降级 InMemory |
| MLX 模型下载失败（网络） | 中 | S3 无法用 | 提供 KeywordEmbedder 永远可用降级；模型文件也可手动放置 |
| SQLite BLOB 解码字节序问题 | 低 | 向量乱码 | 验证 Float32 little-endian；XiaoNuo 用 Node Buffer（LE），Swift 默认 LE |
| 大库全量扫描慢（>100K 向量） | 低 | 延迟 > 200ms | S4 后预留 IVF 接口；当前 13K 无压力 |

---

## 十二、文件清单（本轮新增/修改）

### 新增
| 文件 | 阶段 |
|---|---|
| `Knowledge/EmbeddingProvider.swift` | S1 |
| `Knowledge/SemanticIndex.swift` | S1 |
| `Knowledge/KeywordEmbedder.swift` | S2 |
| `Knowledge/InMemoryVectorIndex.swift` | S2 |
| `Knowledge/MLXEmbeddingProvider.swift` | S3 |
| `Knowledge/SQLiteVectorIndex.swift` | S4 |
| `Tests/EmbeddingProviderTests.swift` | S2/S3 |
| `Tests/SemanticIndexTests.swift` | S2/S4 |

### 修改
| 文件 | 阶段 | 改动 |
|---|---|---|
| `Knowledge/RuleEngine.swift` | S2 | 重构为六步管道 + 依赖注入 |
| `Knowledge/WikiAdapter.swift` | S2 | `retrieveRules` 委托给 RuleEngine；新增 `lookupConcepts`/`readPages` |
| `Loop/PatentLoopEngine.swift` | S5 | 注入 RuleEngine，Step 2 调用真实检索 |
| `App/Views/Settings/KnowledgeSettingsView.swift` | S5 | 三档模式 + MLX 模型 + 索引路径 + 测试检索 |
| `Packages/YunPatCore/Package.swift` | S3 | 新增 mlx-swift-extras 依赖 |
| `Tools/TypedKnowledgeSearchTool.swift` | S5 | searcher 闭包接入 SemanticIndex |

---

## 附录 A：XiaoNuo Agent 知识库 schema 完整参考

来源：`packages/knowledge/src/indexer/schema.ts`

```
documents
  id              TEXT PK
  source          TEXT (wiki|raw|law|guideline|trademark)
  doc_type        TEXT (concept|card|case|judgment|guideline_rule|law_article|...)
  domain          TEXT (patent|trademark|copyright|general_law)
  title           TEXT
  file_path       TEXT
  module          TEXT
  priority        TEXT
  level           TEXT
  publish_date    TEXT
  case_number     TEXT
  court           TEXT
  decision_number TEXT
  article_number  TEXT
  content_hash    TEXT
  indexed_at      TEXT
  char_count      INTEGER
  chunk_count     INTEGER

chunks
  id            INTEGER PK
  document_id   TEXT FK→documents
  chunk_index   INTEGER
  chunk_type    TEXT
  heading       TEXT
  content       TEXT
  char_count    INTEGER

embeddings
  id          INTEGER PK
  chunk_id    INTEGER FK→chunks
  document_id TEXT FK→documents
  vector      BLOB (Float32Array, 1024 dims, little-endian)
  model       TEXT (default 'bge-m3')
  dim         INTEGER (default 1024)
  norm        REAL (L2 norm, 预存优化)
  indexed_at  TEXT
```

## 附录 B：检索 SQL 模板

```sql
-- 无过滤的全量扫描检索
SELECT
    e.chunk_id, e.document_id, e.vector, e.norm,
    c.content AS chunk_content, c.heading AS chunk_heading,
    d.title, d.source, d.doc_type, d.module
FROM embeddings e
JOIN chunks c ON e.chunk_id = c.id
JOIN documents d ON e.document_id = d.id
-- WHERE d.domain = 'patent'        -- 可选过滤
--   AND d.module IN ('专利实务')   -- 可选过滤
ORDER BY e.id                       -- keyset pagination 用
-- Swift 端逐行计算余弦相似度 + topK 堆
```
