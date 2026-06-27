import Foundation

public final class ContextEngine: @unchecked Sendable {
    public init() {}

    public func buildPrompt(for request: UserRequest, flow: AgentFlow, maxTokenBudget: Int = 4000) async throws -> String {
        var parts: [String] = []
        parts.append("你是一个有用的 AI 助手。")
        parts.append("用户：\(request.content)")
        let full = parts.joined(separator: "\n\n")
        let estimatedTokens = full.count / 4
        if estimatedTokens > maxTokenBudget {
            return String(full.prefix(maxTokenBudget * 4))
        }
        return full
    }
}
