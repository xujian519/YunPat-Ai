import Foundation

/// Function calling 工具定义 — 供 LLM function calling API 使用，描述工具的名称、用途和参数 schema
public struct ChatToolDefinition: Sendable {
    public let name: String
    public let description: String
    /// JSON Schema 参数字符串（默认 "{}" 表示无参数）
    public let parameters: String
    public init(name: String, description: String, parameters: String = "{}") {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct ChatRequest: Sendable {
    public let model: String
    public let messages: [Message]
    public let systemPrompt: String?
    public let temperature: Float?
    public let maxTokens: Int?
    public let tools: [ChatToolDefinition]?
    public init(
        model: String, messages: [Message], systemPrompt: String? = nil, temperature: Float? = nil,
        maxTokens: Int? = nil, tools: [ChatToolDefinition]? = nil
    ) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.tools = tools
    }
}
