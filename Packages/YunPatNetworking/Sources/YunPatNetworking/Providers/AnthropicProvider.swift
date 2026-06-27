import Foundation

public final class AnthropicProvider: ModelBackend {
    public let provider = ModelProvider.anthropic
    private let apiKey: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1")!

    public init(apiKey: String) { self.apiKey = apiKey }
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
    public func capabilities() -> ModelCapabilities {
        ModelCapabilities(supportsStreaming: true, supportsToolCalling: true, maxContextTokens: 200_000)
    }
    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy { .retry(after: error.retryAfter ?? 5.0) }
}
