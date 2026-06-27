import Foundation
import YunPatNetworking

public final class MockModelBackend: ModelBackend {
    public let provider: ModelProvider
    public let mockResponse: String
    public let shouldFail: Bool

    public init(provider: ModelProvider = .openai, mockResponse: String = "Mock response", shouldFail: Bool = false) {
        self.provider = provider; self.mockResponse = mockResponse; self.shouldFail = shouldFail
    }

    public var rateLimit: RateLimitInfo? { get async { nil } }

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            if shouldFail { continuation.finish(throwing: RateLimitError(message: "Mock failure")); return }
            for char in mockResponse { continuation.yield(.text(String(char))) }
            continuation.yield(.finish(reason: .stop, usage: nil))
            continuation.finish()
        }
    }

    public func listModels() async throws -> [ModelInfo] { [] }
    public func capabilities() -> ModelCapabilities { ModelCapabilities() }
    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy { .fail }
}
