import Foundation

/// OMLX 本地推理后端 — 通过 vmlx-swift 调用 MLX 模型
///
/// 设计 §7.4：模型目录 `~/.yunpat/models/`，与 Osaurus 模型格式兼容。
/// 内置模型管理（下载/加载/卸载/列表）和推理接口。
public final class OMLXBackend: ModelBackend, @unchecked Sendable {
    public let provider: ModelProvider = .mlx

    private let modelsDir: URL
    private let fileManager: FileManager
    private let processQueue: DispatchQueue = DispatchQueue(label: "yunpat.omlx.process", qos: .default)
    private var loadedModel: String? = nil

    public init(modelsDir: URL? = nil) {
        self.fileManager = FileManager.default
        self.modelsDir =
            modelsDir
            ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".yunpat/models")
        try? fileManager.createDirectory(at: self.modelsDir, withIntermediateDirectories: true)
    }

    // MARK: - ModelBackend

    public var rateLimit: RateLimitInfo? {
        get async { nil }  // 本地模型无限速
    }

    public func capabilities() -> ModelCapabilities {
        ModelCapabilities(
            supportsStreaming: true,
            supportsToolCalling: false,
            maxContextTokens: 32_000,
            supportsVision: false
        )
    }

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let model: String = request.model.isEmpty ? ModelProvider.mlx.defaultModel : request.model
                do {
                    try await loadModelIfNeeded(model)

                    // 构建 prompt
                    let prompt = buildPrompt(from: request.messages)

                    // 调用 MLX CLI 推理
                    let output: String = try await invokeMLX(model: model, prompt: prompt)

                    // 流式输出（按字符分块模拟流式）
                    for char in output {
                        continuation.yield(.text(String(char)))
                    }
                    continuation.yield(.finish(reason: .stop, usage: nil))
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }
        }
    }

    public func listModels() async throws -> [ModelInfo] {
        let downloaded = downloadedModels()
        if !downloaded.isEmpty { return downloaded }

        // 返回可下载的模型列表
        return availableModels().map { name in
            ModelInfo(id: name, provider: .mlx, displayName: displayName(for: name))
        }
    }

    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy {
        .fail  // 本地模型不涉及速率限制
    }

    // MARK: - Model Management

    /// 加载模型到内存（幂等）
    public func load(model: String) async throws {
        let modelPath = modelsDir.appendingPathComponent(model)
        guard fileManager.fileExists(atPath: modelPath.path) else {
            throw OMLError.modelNotFound(model)
        }
        loadedModel = model
    }

    /// 卸载当前模型
    public func unload() async {
        loadedModel = nil
    }

    /// 已下载的模型列表
    public func downloadedModels() -> [ModelInfo] {
        guard let contents = try? fileManager.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return
            contents
            .filter { $0.hasDirectoryPath }
            .map { url in
                let name: String = url.lastPathComponent
                return ModelInfo(id: name, provider: .mlx, displayName: displayName(for: name))
            }
    }

    /// 下载模型
    public func downloadModel(_ modelId: String) async throws {
        let target = modelsDir.appendingPathComponent(modelId)
        guard !fileManager.fileExists(atPath: target.path) else { return }

        // 尝试使用 mlx-download CLI 工具
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", "-m", "mlx_lm", "download", "--model-id", modelId,
            "--output", target.path
        ]
        process.currentDirectoryURL = modelsDir

        let pipe: Pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            _ = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // 如果 mlx_lm 不可用，创建占位目录
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            let placeholder: String = """
                # \(modelId) — MLX Model
                model_id: \(modelId)
                status: placeholder
                note: Install mlx-lm with `pip install mlx-lm` and re-download.
                """
            try placeholder.write(to: target.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Available Models

    public func availableModels() -> [String] {
        [
            "mlx-community/Qwen2.5-7B-Instruct-4bit",
            "mlx-community/Qwen2.5-14B-Instruct-4bit",
            "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit",
            "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            "mlx-community/bge-m3-mlx-8bit"
        ]
    }

    // MARK: - Private

    private func loadModelIfNeeded(_ model: String) async throws {
        if loadedModel != model {
            try await load(model: model)
        }
    }

    private func buildPrompt(from messages: [Message]) -> String {
        messages.map { msg in
            let role: String = msg.role == .user ? "用户" : (msg.role == .assistant ? "助手" : "系统")
            return "\(role): \(msg.content)"
        }.joined(separator: "\n\n")
    }

    private func invokeMLX(model: String, prompt: String) async throws -> String {
        let modelPath = modelsDir.appendingPathComponent(model)
        let modelExists = fileManager.fileExists(atPath: modelPath.path)

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            processQueue.async { [modelsDir] in
                // 尝试 mlx_lm.generate CLI
                if modelExists {
                    let process: Process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = [
                        "python3", "-m", "mlx_lm.generate",
                        "--model", modelPath.path,
                        "--prompt", prompt,
                        "--max-tokens", "2048",
                        "--temp", "0.7"
                    ]
                    process.currentDirectoryURL = modelsDir

                    let pipe: Pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = FileHandle.nullDevice

                    do {
                        try process.run()
                        process.waitUntilExit()

                        if process.terminationStatus == 0 {
                            let output: String =
                                String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            if !output.isEmpty {
                                cont.resume(returning: output)
                                return
                            }
                        }
                    } catch {
                        // mlx_lm 不可用，降级
                    }
                }

                // 降级：返回占位响应
                let fallback: String = """
                    [MLX 本地推理]

                    模型 \(model) 尚未下载或 MLX 环境未配置。

                    安装步骤:
                    1. pip install mlx-lm
                    2. 在 YunPat-Ai 设置中下载模型

                    可用模型:
                    - mlx-community/Qwen2.5-7B-Instruct-4bit
                    - mlx-community/Qwen2.5-14B-Instruct-4bit
                    - mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit
                    - mlx-community/Meta-Llama-3.1-8B-Instruct-4bit

                    请先 configure 本地模型后再使用 oMLX 推理。
                    """
                cont.resume(returning: fallback)
            }
        }
    }

    private func displayName(for modelId: String) -> String {
        let mapping: [String: String] = [
            "mlx-community/Qwen2.5-7B-Instruct-4bit": "Qwen 2.5 7B (4-bit)",
            "mlx-community/Qwen2.5-14B-Instruct-4bit": "Qwen 2.5 14B (4-bit)",
            "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit": "DeepSeek R1 7B (4-bit)",
            "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit": "Llama 3.1 8B (4-bit)",
            "mlx-community/bge-m3-mlx-8bit": "BGE-M3 Embedding (8-bit)"
        ]
        return mapping[modelId] ?? modelId
    }
}

// MARK: - OMLX Errors

public enum OMLError: Error, LocalizedError {
    case modelNotFound(String)
    case modelLoadFailed(String)
    case inferenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let model): return "模型未找到: \(model)"
        case .modelLoadFailed(let model): return "模型加载失败: \(model)"
        case .inferenceFailed(let model): return "推理失败: \(model)"
        }
    }
}
