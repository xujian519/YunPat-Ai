import Foundation

public final class OpenAIProvider: ModelBackend {
    public let provider = ModelProvider.openai
    private let apiKey: String
    private let baseURL: URL
    private let session = URLSession.shared

    public init(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public var rateLimit: RateLimitInfo? { get async { nil } }

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            guard !apiKey.isEmpty else {
                continuation.finish(throwing: RateLimitError(message: "API key is empty"))
                return
            }
            continuation.yield(.error(RateLimitError(message: "Not yet implemented")))
            continuation.finish()
        }
    }

    public func listModels() async throws -> [ModelInfo] { [] }
    public func capabilities() -> ModelCapabilities {
        ModelCapabilities(supportsStreaming: true, supportsToolCalling: true, maxContextTokens: 128_000, supportsVision: true)
    }
    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy { .retry(after: error.retryAfter ?? 5.0) }
}
