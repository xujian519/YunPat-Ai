import Foundation

public enum ModelProvider: String, Codable, Sendable, CaseIterable {
    case openai
    case anthropic
    case deepseek
    case glm
    case qwen
    case openrouter
    case siliconflow
    case mistral
    case together
    case mlx
    case ollama

    public static let allCloud: [ModelProvider] = [
        .openai, .anthropic, .deepseek, .glm, .qwen,
        .openrouter, .siliconflow, .mistral, .together
    ]

    public static let allLocal: [ModelProvider] = [.mlx, .ollama]

    public var isLocal: Bool { Self.allLocal.contains(self) }

    public var defaultModel: String {
        ProviderDefinition.definition(for: self).defaultModel
    }

    public var defaultCapabilities: ModelCapabilities {
        ProviderDefinition.definition(for: self).capabilities
    }
}

public struct ProviderDefinition: Sendable, Identifiable {
    public var id: ModelProvider { provider }
    public let provider: ModelProvider
    public let displayName: String
    public let icon: String
    public let defaultBaseURL: String
    public let defaultModel: String
    public let docURL: String?
    public let capabilities: ModelCapabilities

    public static let all: [ProviderDefinition] = [
        ProviderDefinition(
            provider: .openai, displayName: "OpenAI", icon: "brain.head.profile",
            defaultBaseURL: "https://api.openai.com/v1", defaultModel: "gpt-4o",
            docURL: "https://platform.openai.com/api-keys",
            capabilities: ModelCapabilities(supportsToolCalling: true, supportsVision: true)
        ),
        ProviderDefinition(
            provider: .anthropic, displayName: "Anthropic", icon: "leaf.fill",
            defaultBaseURL: "https://api.anthropic.com/v1", defaultModel: "claude-sonnet-4-20250514",
            docURL: "https://console.anthropic.com/",
            capabilities: ModelCapabilities(supportsToolCalling: true, maxContextTokens: 200_000, supportsVision: true)
        ),
        ProviderDefinition(
            provider: .deepseek, displayName: "DeepSeek", icon: "bolt.fill",
            defaultBaseURL: "https://api.deepseek.com/v1", defaultModel: "deepseek-v4-flash",
            docURL: "https://platform.deepseek.com/api_keys",
            capabilities: ModelCapabilities(supportsToolCalling: true, maxContextTokens: 1_000_000)
        ),
        ProviderDefinition(
            provider: .glm, displayName: "GLM (智谱)", icon: "star.fill",
            defaultBaseURL: "https://open.bigmodel.cn/api/paas/v4", defaultModel: "glm-4-plus",
            docURL: "https://open.bigmodel.cn/usercenter/apikeys",
            capabilities: ModelCapabilities(supportsToolCalling: true)
        ),
        ProviderDefinition(
            provider: .qwen, displayName: "Qwen (通义千问)", icon: "cloud.fill",
            defaultBaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            defaultModel: "qwen-plus",
            docURL: "https://help.aliyun.com/zh/model-studio/",
            capabilities: ModelCapabilities(supportsToolCalling: true, maxContextTokens: 128_000, supportsVision: true)
        ),
        ProviderDefinition(
            provider: .openrouter, displayName: "OpenRouter", icon: "arrow.triangle.branch",
            defaultBaseURL: "https://openrouter.ai/api/v1", defaultModel: "openai/gpt-4o",
            docURL: "https://openrouter.ai/keys",
            capabilities: ModelCapabilities(supportsToolCalling: true, maxContextTokens: 128_000)
        ),
        ProviderDefinition(
            provider: .siliconflow, displayName: "SiliconFlow (硅基流动)", icon: "cpu",
            defaultBaseURL: "https://api.siliconflow.cn/v1", defaultModel: "Qwen/Qwen2.5-7B-Instruct",
            docURL: "https://cloud.siliconflow.cn/",
            capabilities: ModelCapabilities(supportsToolCalling: true, maxContextTokens: 32_000)
        ),
        ProviderDefinition(
            provider: .mistral, displayName: "Mistral AI", icon: "wind",
            defaultBaseURL: "https://api.mistral.ai/v1", defaultModel: "mistral-large-latest",
            docURL: "https://console.mistral.ai/api-keys/",
            capabilities: ModelCapabilities(supportsToolCalling: true, maxContextTokens: 128_000)
        ),
        ProviderDefinition(
            provider: .together, displayName: "Together AI", icon: "square.grid.3x3",
            defaultBaseURL: "https://api.together.xyz/v1", defaultModel: "meta-llama/Llama-3.3-70B-Instruct-Turbo",
            docURL: "https://api.together.ai/settings/api-keys",
            capabilities: ModelCapabilities(supportsToolCalling: true, maxContextTokens: 128_000)
        ),
        ProviderDefinition(
            provider: .mlx, displayName: "MLX (本地)", icon: "macmini",
            defaultBaseURL: "", defaultModel: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            docURL: nil,
            capabilities: ModelCapabilities(supportsStreaming: true, maxContextTokens: 32_000)
        ),
        ProviderDefinition(
            provider: .ollama, displayName: "Ollama (本地)", icon: "desktopcomputer",
            defaultBaseURL: "http://localhost:11434/v1", defaultModel: "llama3",
            docURL: "https://ollama.ai/",
            capabilities: ModelCapabilities(supportsStreaming: true, maxContextTokens: 8_000)
        )
    ]

    public static func definition(for provider: ModelProvider) -> ProviderDefinition {
        if let def = all.first(where: { $0.provider == provider }) {
            return def
        }
        return all[0]  // openai — guaranteed by static init
    }
}

public struct ModelInfo: Codable, Sendable {
    public let id: String
    public let provider: ModelProvider
    public let displayName: String
    public init(id: String, provider: ModelProvider, displayName: String) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
    }
}

public struct ModelCapabilities: Sendable {
    public let supportsStreaming: Bool
    public let supportsToolCalling: Bool
    public let maxContextTokens: Int
    public let supportsVision: Bool
    public init(
        supportsStreaming: Bool = true, supportsToolCalling: Bool = false, maxContextTokens: Int = 128_000,
        supportsVision: Bool = false
    ) {
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.maxContextTokens = maxContextTokens
        self.supportsVision = supportsVision
    }
}

public struct RateLimitInfo: Sendable {
    public let remainingRequests: Int
    public let remainingTokens: Int
    public let resetAt: Date
    public init(remainingRequests: Int, remainingTokens: Int, resetAt: Date) {
        self.remainingRequests = remainingRequests
        self.remainingTokens = remainingTokens
        self.resetAt = resetAt
    }
}

public struct RateLimitError: Error, Sendable {
    public let retryAfter: TimeInterval?
    public let message: String
    public init(retryAfter: TimeInterval? = nil, message: String = "Rate limit exceeded") {
        self.retryAfter = retryAfter
        self.message = message
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
