import Foundation

public enum ModelProvider: String, Codable, Sendable {
    case openai
    case anthropic
    case deepseek
    case glm
}

public struct ModelInfo: Codable, Sendable {
    public let id: String
    public let provider: ModelProvider
    public let displayName: String
    public init(id: String, provider: ModelProvider, displayName: String) {
        self.id = id; self.provider = provider; self.displayName = displayName
    }
}

public struct ModelCapabilities: Sendable {
    public let supportsStreaming: Bool
    public let supportsToolCalling: Bool
    public let maxContextTokens: Int
    public let supportsVision: Bool
    public init(supportsStreaming: Bool = true, supportsToolCalling: Bool = false, maxContextTokens: Int = 128_000, supportsVision: Bool = false) {
        self.supportsStreaming = supportsStreaming; self.supportsToolCalling = supportsToolCalling; self.maxContextTokens = maxContextTokens; self.supportsVision = supportsVision
    }
}

public struct RateLimitInfo: Sendable {
    public let remainingRequests: Int
    public let remainingTokens: Int
    public let resetAt: Date
    public init(remainingRequests: Int, remainingTokens: Int, resetAt: Date) {
        self.remainingRequests = remainingRequests; self.remainingTokens = remainingTokens; self.resetAt = resetAt
    }
}

public struct RateLimitError: Error, Sendable {
    public let retryAfter: TimeInterval?
    public let message: String
    public init(retryAfter: TimeInterval? = nil, message: String = "Rate limit exceeded") {
        self.retryAfter = retryAfter; self.message = message
    }
}

public enum RetryStrategy: Sendable {
    case retry(after: TimeInterval)
    case fail
    case switchProvider(ModelProvider)
}

public protocol ModelBackend: Sendable {
    var provider: ModelProvider { get }
    var rateLimit: RateLimitInfo? { get async }
    func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error>
    func listModels() async throws -> [ModelInfo]
    func capabilities() -> ModelCapabilities
    func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy
}
