import Foundation

/// 上下文引擎 — 根据请求和流程模式构建 system prompt，集成技能匹配
///
/// 集成技能匹配（SkillManager），将匹配的技能注入到 prompt 中。
public final class ContextEngine: @unchecked Sendable {
    private let skillManager: SkillManager?

    public init(skillManager: SkillManager? = nil) {
        self.skillManager = skillManager
    }

    /// 构建 system prompt
    ///
    /// - Parameters:
    ///   - request: 用户请求（含 content 和 attachments）
    ///   - flow: 对话流程模式
    ///   - maxTokenBudget: 最大 token 预算（超出时截断），默认 4000
    /// - Returns: 完整的 system prompt 文本
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
