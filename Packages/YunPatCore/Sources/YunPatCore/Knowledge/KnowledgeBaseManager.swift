import Foundation

/// 知识库生命周期管理器 — 统一管理 MLXEmbeddingProvider + LegacySemanticIndex 的初始化、接线与清理
///
/// 职责：
/// 1. 根据 vaultPath 创建 MLXEmbeddingProvider 和 LegacySemanticIndex
/// 2. 注入到共享 WikiAdapter
/// 3. 设置 VectorSearch.shared.embedHandler
/// 4. 响应 vault 路径变更（重新初始化或清理）
///
/// 使用方式（App 启动时）：
/// ```swift
/// if let vaultPath = UserDefaults.standard.string(forKey: "yunpat.vaultPath") {
///     await KnowledgeBaseManager.shared.configure(vaultPath: URL(filePath: vaultPath))
/// }
/// ```
public actor KnowledgeBaseManager {

    public static let shared = KnowledgeBaseManager()

    /// 当前配置的知识库路径
    public private(set) var vaultPath: URL?

    /// 共享的 WikiAdapter（embeddingProvider + semanticIndex 已注入）
    public private(set) var wikiAdapter: WikiAdapter?

    /// Embedding 提供者（MLX 本地推理）
    public private(set) var embeddingProvider: MLXEmbeddingProvider?

    /// 语义索引（包装 .yunpat-semantic-index.sqlite）
    public private(set) var semanticIndex: LegacySemanticIndex?

    /// 是否已正确配置
    public var isConfigured: Bool { wikiAdapter != nil }

    private init() {}

    /// 配置知识库 — 创建设置所有组件并接线
    /// - Parameter vaultPath: Obsidian Vault 根路径
    /// - Throws: `KnowledgeBaseError` 当关键组件初始化失败时
    public func configure(vaultPath: URL) async throws {
        self.vaultPath = vaultPath

        // 1. 创建 MLXEmbeddingProvider（lazy load，首次 embed() 时下载模型）
        //    使用已缓存的 mlx-community/bge-m3-mlx-8bit
        let embedder = MLXEmbeddingProvider(modelId: "mlx-community/bge-m3-mlx-8bit")
        self.embeddingProvider = embedder

        // 2. 创建 LegacySemanticIndex 包装已有的 .yunpat-semantic-index.sqlite
        let indexPath = vaultPath.appendingPathComponent(".yunpat-semantic-index.sqlite")
        if FileManager.default.fileExists(atPath: indexPath.path) {
            let index = LegacySemanticIndex(dbPath: indexPath)
            self.semanticIndex = index
        } else {
            self.semanticIndex = nil
        }

        // 3. 创建 WikiAdapter 并注入 embeddingProvider + semanticIndex
        let adapter = WikiAdapter(
            vaultPath: vaultPath,
            embeddingProvider: embedder,
            semanticIndex: semanticIndex
        )
        self.wikiAdapter = adapter

        // 4. 设置 VectorSearch.shared.embedHandler → 使用 MLXEmbeddingProvider
        let providerRef: MLXEmbeddingProvider = embedder
        await VectorSearch.shared.setEmbedHandler { [providerRef] texts in
            do {
                return try await providerRef.embed(texts)
            } catch {
                print("[KnowledgeBaseManager] VectorSearch embed failed: \(error)")
                return nil
            }
        }
    }

    /// 重置 — 清空所有组件（vault 路径变更时调用）
    public func reset() {
        vaultPath = nil
        wikiAdapter = nil
        embeddingProvider = nil
        semanticIndex = nil
    }

    /// 重新加载 — vault 路径不变时刷新索引连接（如 SQLite 文件被覆盖）
    public func reload() async throws {
        guard let path = vaultPath else { return }
        try await configure(vaultPath: path)
    }
}
