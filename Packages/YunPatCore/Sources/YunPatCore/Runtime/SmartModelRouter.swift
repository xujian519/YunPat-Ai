import Foundation
import YunPatNetworking

/// 智能模型路由器 — 按任务特征自动选择最佳模型
///
/// 设计 §7：摘要→廉价模型，撰写→强推理模型，检索→长上下文模型
public struct SmartModelRouter: Sendable {
    public enum TaskCategory: String, Sendable {
        case summary  // 摘要/压缩
        case drafting  // 撰写/起草
        case retrieval  // 检索/查询
        case analysis  // 分析/推理
        case general  // 通用对话
    }

    /// 根据请求内容推断任务类别
    public static func classify(_ request: UserRequest) -> TaskCategory {
        let content: String = request.content.lowercased()

        // 撰写类关键词
        let draftingKeywords: [String] = ["撰写", "权利要求", "说明书", "起草", "独立权利要求", "从属权利要求"]
        if draftingKeywords.contains(where: { content.contains($0) }) {
            return .drafting
        }

        // 检索类关键词
        let retrievalKeywords: [String] = ["检索", "搜索", "查找", "查询", "法律状态", "专利号"]
        if retrievalKeywords.contains(where: { content.contains($0) }) {
            return .retrieval
        }

        // 分析类关键词
        let analysisKeywords = ["分析", "创造性", "新颖性", "三步法", "侵权", "对比", "无效"]
        if analysisKeywords.contains(where: { content.contains($0) }) {
            return .analysis
        }

        // 摘要类
        if content.contains("总结") || content.contains("摘要") || content.contains("概括") {
            return .summary
        }

        return .general
    }

    /// 根据任务类别选择最佳模型
    public static func selectModel(for category: TaskCategory, preferred: ModelProvider = .deepseek) -> String {
        switch preferred {
        case .deepseek:
            switch category {
            case .summary: return "deepseek-chat"
            case .drafting: return "deepseek-reasoner"
            case .retrieval: return "deepseek-chat"
            case .analysis: return "deepseek-reasoner"
            case .general: return "deepseek-chat"
            }

        case .openai:
            switch category {
            case .summary: return "gpt-4o-mini"
            case .drafting: return "gpt-4o"
            case .retrieval: return "gpt-4o"
            case .analysis: return "gpt-4o"
            case .general: return "gpt-4o"
            }

        case .anthropic:
            switch category {
            case .summary: return "claude-sonnet-4-20250514"
            case .drafting: return "claude-sonnet-4-20250514"
            case .retrieval: return "claude-sonnet-4-20250514"  // 200K context
            case .analysis: return "claude-sonnet-4-20250514"
            case .general: return "claude-sonnet-4-20250514"
            }

        case .glm:
            switch category {
            case .summary: return "glm-4-flash"
            case .drafting: return "glm-4"
            case .retrieval: return "glm-4"
            case .analysis: return "glm-4"
            case .general: return "glm-4"
            }

        case .ollama, .mlx:
            return preferred.defaultModel
        default:
            return preferred.defaultModel
        }
    }
}
