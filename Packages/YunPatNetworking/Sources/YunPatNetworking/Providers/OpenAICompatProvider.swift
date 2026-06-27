import Foundation

/// OpenAI 兼容端点 provider — 用于 DeepSeek、GLM 等兼容 OpenAI Chat Completions API 的服务商。
///
/// 复用 OpenAIProvider 的 SSE 流式解析逻辑，仅替换 baseURL 和 provider 标识。
public final class OpenAICompatProvider: ModelBackend {
    public let provider: ModelProvider
    private let impl: OpenAIProvider

    public init(apiKey: String, baseURL: URL, provider: ModelProvider) {
        self.provider = provider
        self.impl = OpenAIProvider(apiKey: apiKey, baseURL: baseURL, provider: provider)
    }

    public var rateLimit: RateLimitInfo? { get async { await impl.rateLimit } }

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        impl.chat(request)
    }

    public func listModels() async throws -> [ModelInfo] { try await impl.listModels() }

    public func capabilities() -> ModelCapabilities { impl.capabilities() }

    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy {
        await impl.onRateLimitExceeded(error)
    }
}
