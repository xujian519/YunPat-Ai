import Foundation

public struct ChatRequest: Sendable {
    public let model: String
    public let messages: [Message]
    public let systemPrompt: String?
    public let temperature: Float?
    public let maxTokens: Int?
    public init(
        model: String, messages: [Message], systemPrompt: String? = nil, temperature: Float? = nil,
        maxTokens: Int? = nil
    ) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}
