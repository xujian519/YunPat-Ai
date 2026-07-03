import Foundation

/// Flow 模式自动分类器 — 根据用户请求内容判断 Copilot / Guided / FullAgent
///
/// 设计 §2：轻量 LLM 分类 + 标签设置覆盖
/// 当前实现：基于关键词 + 模式匹配的启发式分类（无需额外 LLM 调用）
/// 未来可升级为轻量 LLM 分类
public struct FlowClassifier: Sendable {

    public init() {}

    /// 根据用户请求内容判断 Flow 模式
    public func classify(_ request: String) -> AgentFlow {
        let lower: String = request.lowercased()

        if isCopilot(lower) { return .copilot }
        if isFullAgent(lower) { return .fullAgent }
        return .guided
    }

    // Copilot：简单查询、术语解释、格式调整
    private func isCopilot(_ text: String) -> Bool {
        let copilotTriggers: [String] = [
            "什么是", "解释", "帮我看看", "翻译", "格式", "检查拼写",
            "总结一下", "帮我改", "替换", "这是什么意思", "区别是什么",
            "定义", "含义", "缩写"
        ]
        // 短文本（< 50 字符）+ 疑问句式 → Copilot
        if text.count < 50 {
            for trigger in copilotTriggers where text.localizedCaseInsensitiveContains(trigger) {
                return true
            }
        }
        return false
    }

    // FullAgent：完整撰写、OA 答复、无效宣告、侵权分析
    private func isFullAgent(_ text: String) -> Bool {
        let fullAgentTriggers: [String] = [
            "撰写权利要求", "起草权利要求", "撰写说明书", "起草说明书",
            "答复审查意见", "答复OA", "OA答复", "审查意见答复",
            "无效宣告", "无效请求", "专利无效",
            "侵权分析", "侵权判定", "特征对比",
            "完整撰写", "全流程", "从零开始"
        ]
        for trigger in fullAgentTriggers where text.localizedCaseInsensitiveContains(trigger) {
            return true
        }
        // 长文本（> 200 字符）的复杂请求 → FullAgent
        if text.count > 500 { return true }
        return false
    }
}
