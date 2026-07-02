import Foundation

public final class ContextEngine: @unchecked Sendable {
    private let skillManager: SkillManager?

    public init(skillManager: SkillManager? = nil) {
        self.skillManager = skillManager
    }

    public func buildPrompt(for request: UserRequest, flow: AgentFlow, maxTokenBudget: Int = 4000) async throws
        -> String {
        var parts: [String] = []
        parts.append("你是一个有用的 AI 助手。")

        if let skillManager {
            let matches: [SkillMatch] = await skillManager.match(for: request)
            if !matches.isEmpty {
                var skillLines: [String] = []
                for model in matches.prefix(3) {
                    skillLines.append("## \(model.skill.manifest.displayName)\n\(model.skill.body)")
                }
                parts.append("【启用的技能】\n\(skillLines.joined(separator: "\n\n"))")
            }
        }

        parts.append("用户：\(request.content)")
        let full = parts.joined(separator: "\n\n")
        let estimatedTokens: Int = full.count / 4
        if estimatedTokens > maxTokenBudget {
            return String(full.prefix(maxTokenBudget * 4))
        }
        return full
    }
}
