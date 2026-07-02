import Foundation
import YunPatNetworking

public final class MockModelBackend: ModelBackend {
    public let provider: ModelProvider
    public let mockResponse: String
    public let shouldFail: Bool
    private let chunks: [ChatChunk]?

    public init(
        provider: ModelProvider = .openai,
        mockResponse: String = "Mock response",
        shouldFail: Bool = false,
        chunks: [ChatChunk]? = nil
    ) {
        self.provider = provider
        self.mockResponse = mockResponse
        self.shouldFail = shouldFail
        self.chunks = chunks
    }

    public var rateLimit: RateLimitInfo? { get async { nil } }

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            if shouldFail {
                continuation.finish(throwing: RateLimitError(message: "Mock failure"))
                return
            }
            if let chunks = self.chunks {
                for chunk in chunks { continuation.yield(chunk) }
            } else {
                for char in mockResponse { continuation.yield(.text(String(char))) }
                continuation.yield(.finish(reason: .stop, usage: nil))
            }
            continuation.finish()
        }
    }

    public func listModels() async throws -> [ModelInfo] { [] }
    public func capabilities() -> ModelCapabilities { ModelCapabilities() }
    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy { .fail }
}
