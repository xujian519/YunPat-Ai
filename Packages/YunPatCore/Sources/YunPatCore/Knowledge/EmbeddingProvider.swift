import Foundation

/// 文本向量化提供者协议 — 将文本编码为语义向量供语义检索使用
///
/// 实现：
/// - ``MLXEmbeddingProvider``（主力，bge-m3-mlx-8bit 原生推理）
/// - ``KeywordEmbedder``（开发 mock，零依赖降级）
public protocol EmbeddingProvider: Sendable {

    /// 向量维度（bge-m3 = 1024）
    var dimension: Int { get }

    /// 模型标识，用于与索引的 `embeddings.model` 列校验
    var modelName: String { get }

    /// 是否已就绪可调用（MLX 需异步加载，首次调用前为 false）
    var isReady: Bool { get async }

    /// 批量向量化
    /// - Parameter texts: 待编码文本数组
    /// - Returns: 与 texts 等长的向量数组，每个向量长度 == dimension，L2 归一化
    func embed(_ texts: [String]) async throws -> [[Float]]
}
