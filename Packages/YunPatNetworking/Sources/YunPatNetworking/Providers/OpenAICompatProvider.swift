import Foundation

public final class OpenAICompatProvider: ModelBackend {
    public let provider: ModelProvider
    private let apiKey: String
    private let baseURL: URL

    public init(apiKey: String, baseURL: URL, provider: ModelProvider) {
        self.apiKey = apiKey; self.baseURL = baseURL; self.provider = provider
    }

    public var rateLimit: RateLimitInfo? { get async { nil } }

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            guard !apiKey.isEmpty else {
                continuation.finish(throwing: RateLimitError(message: "API key is empty"))
                return
            }
            continuation.finish()
        }
    }

    public func listModels() async throws -> [ModelInfo] { [] }
    public func capabilities() -> ModelCapabilities { ModelCapabilities(supportsStreaming: true, supportsToolCalling: true, maxContextTokens: 128_000) }
    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy { .retry(after: error.retryAfter ?? 5.0) }
}
