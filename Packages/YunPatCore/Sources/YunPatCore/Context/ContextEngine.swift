import Foundation
import YunPatNetworking

/// 上下文引擎 — 根据请求和流程模式构建 system prompt，集成技能匹配与上下文压缩
///
/// 集成：
/// - SystemPromptService：专利专用系统提示词（反幻觉规则 + 高效行动规则）
/// - SkillManager：三级 RAG 技能匹配注入
/// - TokenEstimator：CJK 感知的精确 token 估算
/// - CompactionWatermark：KV 稳定的历史消息压缩
public actor ContextEngine {
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
    ///   - provider: 模型提供商（影响 token 估算精度），默认 .openai
    /// - Returns: 完整的 system prompt 文本
    public func buildPrompt(
        for request: UserRequest,
        flow: AgentFlow,
        maxTokenBudget: Int = 4000,
        provider: ModelProvider = .openai
    ) async throws -> String {
        var parts: [String] = []

        // 1. 加载专利专用系统提示词
        let basePrompt: String = await SystemPromptService.shared.prompt()
        parts.append(basePrompt)

        // 2. 注入技能匹配结果
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

        // 3. 追加用户请求上下文
        parts.append("用户：\(request.content)")

        let full = parts.joined(separator: "\n\n")

        // 4. 使用精确 token 估算进行截断
        let estimatedTokens = TokenEstimator.estimate(text: full, provider: provider)
        if estimatedTokens > maxTokenBudget {
            let charsPerToken = TokenEstimator.charsPerToken(for: provider)
            let maxChars = Int(Double(maxTokenBudget) * charsPerToken)
            return String(full.prefix(maxChars))
        }
        return full
    }
}
