import Foundation

#if canImport(MLX)
import MLX
import MLXEmbedders
import MLXLMCommon
import Tokenizers

// MARK: - HF Mirror Downloader

/// HuggingFace 国内镜像下载器 — 实现 `MLXLMCommon.Downloader` 协议
///
/// 默认 endpoint `https://hf-mirror.com`，避免 huggingface.co 国内访问受限。
/// 也支持自定义 endpoint 或通过 `HF_ENDPOINT` 环境变量覆盖。
///
/// 下载流程：
/// 1. GET `{endpoint}/api/models/{repoId}` 获取文件列表
/// 2. 按 glob 模式过滤（如 `*.safetensors`, `*.json`）
/// 3. 逐个用 URLSession 下载到本地缓存目录
/// 4. 已存在的文件自动跳过（增量缓存）
public struct HFMirrorDownloader: MLXLMCommon.Downloader {

    /// 默认国内镜像
    public static let defaultEndpoint: String = "https://hf-mirror.com"

    public let endpoint: String
    public let cacheDir: URL

    /// - Parameters:
    ///   - endpoint: HF 镜像 URL，默认 `https://hf-mirror.com`；读取 `HF_ENDPOINT` 环境变量覆盖
    ///   - cacheDir: 模型缓存目录，默认 `~/.yunpat/models/`
    public init(endpoint: String? = nil, cacheDir: URL? = nil) {
        if let explicit = endpoint {
            self.endpoint = explicit
        } else if let envEndpoint = ProcessInfo.processInfo.environment["HF_ENDPOINT"] {
            self.endpoint = envEndpoint
        } else {
            self.endpoint = Self.defaultEndpoint
        }
        self.cacheDir = cacheDir ?? Self.defaultCacheDir
    }

    public static var defaultCacheDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".yunpat/models")
    }

    // MARK: - Downloader

    public func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let rev: String = revision ?? "main"
        let modelDir: URL = cacheDir.appendingPathComponent(id.replacingOccurrences(of: "/", with: "--"))

        // 1. 获取文件列表
        let allFiles: [String] = try await fetchFileList(repoId: id)

        // 2. 过滤匹配的文件
        let matched: [String]
        if patterns.isEmpty {
            matched = allFiles
        } else {
            matched = allFiles.filter { filename in
                patterns.contains { glob($0, filename) }
            }
        }

        // 3. 创建目录
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // 4. 逐个下载（已存在则跳过）
        let progress = Progress(totalUnitCount: Int64(matched.count))
        progressHandler(progress)

        for filename in matched {
            guard let url = URL(string: "\(endpoint)/\(id)/resolve/\(rev)/\(filename)")
            else { throw MLXEmbeddingError.loadFailed("invalid URL") }
            let dest = modelDir.appendingPathComponent(filename)

            // 创建子目录（如 1_Pooling/）
            let parentDir = dest.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            if !FileManager.default.fileExists(atPath: dest.path) {
                try await downloadFile(url: url, to: dest)
            }
            progress.completedUnitCount += 1
            progressHandler(progress)
        }

        return modelDir
    }

    // MARK: - Internal

    /// GET /api/models/{repoId} → siblings[].rfilename
    private func fetchFileList(repoId: String) async throws -> [String] {
        guard let apiUrl = URL(string: "\(endpoint)/api/models/\(repoId)")
        else { throw MLXEmbeddingError.loadFailed("invalid URL") }
        let (data, response): (Data, URLResponse) = try await URLSession.shared.data(from: apiUrl)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MLXEmbeddingError.loadFailed("无法获取模型文件列表: \(repoId)")
        }

        let decoded = try JSONDecoder().decode(HFAPIResponse.self, from: data)
        return decoded.siblings.map(\.rfilename)
    }

    /// 简单 glob 匹配（支持 `*.ext` 和精确名）
    private func glob(_ pattern: String, _ filename: String) -> Bool {
        if pattern.hasPrefix("*.") {
            let ext = String(pattern.dropFirst(2))
            return filename.hasSuffix(".\(ext)")
        }
        return pattern == filename
    }

    private func downloadFile(url: URL, to dest: URL) async throws {
        let (tempURL, response): (URL, URLResponse) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MLXEmbeddingError.loadFailed("下载失败: \(url.lastPathComponent)")
        }
        // 移动到目标位置
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
    }
}

// MARK: - HF API Response

private struct HFAPIResponse: Decodable {
    let siblings: [HFSibling]
}

private struct HFSibling: Decodable {
    let rfilename: String
}

// MARK: - Tokenizer Bridge

/// 将 swift-transformers 的 `Tokenizers.Tokenizer` 桥接为 `MLXLMCommon.Tokenizer`
/// 用 `@unchecked Sendable` 绕过 Sendable 限制（tokenizer 仅在 actor 内使用）
final class HFTokenizerBridge: MLXLMCommon.Tokenizer, @unchecked Sendable {
    private let upstream: Tokenizers.Tokenizer

    init(_ upstream: Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        throw MLXLMCommon.TokenizerError.missingChatTemplate
    }
}

// MARK: - Tokenizer Loader

/// 从本地目录加载 HuggingFace tokenizer（tokenizer.json + tokenizer_config.json）
struct HFLocalTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer: Tokenizers.Tokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return HFTokenizerBridge(tokenizer)
    }
}

// MARK: - MLXEmbeddingProvider

/// 本地 MLX embedding 提供者 — 通过 Metal GPU 推理 bge-m3 模型生成 1024 维语义向量
///
/// 使用 mlx-swift-lm 的 `EmbedderModelFactory` 加载 BERT/XLM-RoBERTa 模型，
/// 通过 Metal GPU 推理生成 1024 维语义向量。
///
/// 加载模式：
/// - **本地路径**：`init(localModelPath:)` — 直接加载已下载的模型目录
/// - **HuggingFace 下载**：`init(modelId:)` — 首次使用时从 HF Hub 下载
///
/// 首次 `embed()` 调用时懒加载模型（~3s），后续复用。
public actor MLXEmbeddingProvider: EmbeddingProvider {

    public let dimension: Int = 1024
    public let modelName: String = "bge-m3"
    public private(set) var isReady: Bool = false

    private let localModelPath: URL?
    private let modelId: String?
    private var container: EmbedderModelContainer?

    /// 从本地目录加载（不下载）
    /// - Parameter modelPath: 模型目录路径（含 config.json, model.safetensors, tokenizer.json）
    public init(localModelPath: URL) {
        self.localModelPath = localModelPath
        self.modelId = nil
    }

    /// 从 HuggingFace 加载（首次下载，后续从缓存读取）
    /// - Parameter modelId: HuggingFace 模型 ID，默认 "BAAI/bge-m3"
    public init(modelId: String = "BAAI/bge-m3") {
        self.localModelPath = nil
        self.modelId = modelId
    }

    // MARK: - EmbeddingProvider

    /// 批量向量化文本
    ///
    /// - Parameter texts: 待编码文本数组
    /// - Returns: 与 texts 等长的向量数组，每个向量 1024 维，L2 归一化
    /// - Note: 首次调用时懒加载模型（~3s），按 batchSize=16 分批处理
    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        if !isReady { try await loadModel() }
        guard let container else { throw MLXEmbeddingError.modelNotLoaded }

        let batchSize: Int = 16
        var allEmbeddings: [[Float]] = []
        allEmbeddings.reserveCapacity(texts.count)

        for batchStart in stride(from: 0, to: texts.count, by: batchSize) {
            let batchEnd: Int = min(batchStart + batchSize, texts.count)
            let batch: [String] = Array(texts[batchStart..<batchEnd])
            let embeddings: [[Float]] = try await embedBatch(batch, container: container)
            allEmbeddings.append(contentsOf: embeddings)
        }
        return allEmbeddings
    }

    // MARK: - Model Loading

    private func loadModel() async throws {
        let tokenizerLoader: HFLocalTokenizerLoader = HFLocalTokenizerLoader()

        do {
            if let localPath = localModelPath {
                // 本地路径模式
                container = try await EmbedderModelFactory.shared.loadContainer(
                    from: localPath,
                    using: tokenizerLoader
                )
            } else if let modelId {
                // HuggingFace 镜像下载模式
                let downloader: HFMirrorDownloader = HFMirrorDownloader()
                let patterns: [String] = ["*.safetensors", "*.json", "*.txt", "*.model"]
                let modelDir: URL = try await downloader.download(
                    id: modelId, revision: nil,
                    matching: patterns, useLatest: false,
                    progressHandler: { _ in }
                )
                container = try await EmbedderModelFactory.shared.loadContainer(
                    from: modelDir,
                    using: tokenizerLoader
                )
            } else {
                throw MLXEmbeddingError.modelNotLoaded
            }
            isReady = true
        } catch let error as MLXEmbeddingError {
            isReady = false
            throw error
        } catch {
            isReady = false
            throw MLXEmbeddingError.loadFailed(error.localizedDescription)
        }
    }

    // MARK: - Batch Embedding

    private func embedBatch(
        _ texts: [String], container: EmbedderModelContainer
    ) async throws -> [[Float]] {
        try await container.perform { context in
            // Tokenize
            let inputs: [[Int]] = texts.map {
                context.tokenizer.encode(text: $0, addSpecialTokens: true)
            }

            // Pad to longest sequence (至少 16 个 token）
            let padTokenId: Int = context.tokenizer.eosTokenId ?? 0
            let maxLength: Int = inputs.reduce(into: 16) { acc, elem in
                acc = max(acc, elem.count)
            }

            // Stack + pad
            let padded: MLXArray = stacked(
                inputs.map { elem in
                    MLXArray(elem + Array(repeating: padTokenId, count: maxLength - elem.count))
                })

            // Attention mask: 真实 token = true, padding = false
            let mask: MLXArray = (padded .!= padTokenId)
            let tokenTypes: MLXArray = MLXArray.zeros(like: padded)

            // Forward pass
            let modelOutput = context.model(
                padded, positionIds: nil,
                tokenTypeIds: tokenTypes, attentionMask: mask
            )

            // Mean pooling + L2 normalize + LayerNorm
            let pooled: MLXArray = context.pooling(
                modelOutput,
                normalize: true,
                applyLayerNorm: true
            )

            eval(pooled)

            // [batch, dim] → [[Float]]
            let shape: [Int] = pooled.shape
            let batchCount: Int = shape[0]
            let dimCount: Int = shape.count > 1 ? shape[1] : 1024
            let flat: [Float] = pooled.asArray(Float.self)

            var result: [[Float]] = []
            result.reserveCapacity(batchCount)
            for idx in 0..<batchCount {
                let start: Int = idx * dimCount
                let end: Int = start + dimCount
                result.append(Array(flat[start..<end]))
            }
            return result
        }
    }
}

#else

/// MLX 不可用时降级占位 — 所有调用抛出错误，由上层切换到 KeywordEmbedder
public actor MLXEmbeddingProvider: EmbeddingProvider {
    public let dimension: Int = 1024
    public let modelName: String = "bge-m3-unavailable"
    public private(set) var isReady: Bool = false

    public init(localModelPath: URL) {}
    public init(modelId: String = "BAAI/bge-m3") {}

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        throw MLXEmbeddingError.modelNotLoaded
    }
}

#endif

// MARK: - Errors

public enum MLXEmbeddingError: LocalizedError {
    case modelNotLoaded
    case loadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "MLX embedding 模型未加载（MLX 不可用，请使用 KeywordEmbedder 降级）"
        case .loadFailed(let detail):
            return "MLX embedding 模型加载失败: \(detail)"
        }
    }
}
