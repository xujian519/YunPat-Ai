import Foundation
import YunPatNetworking

/// 上下文摘要器 —— Apple Intelligence 主路径 + LLM API 降级
///
/// macOS 26+ 使用 Apple FoundationModels 本地摘要，
/// macOS 15.5 降级为 LLM API 调用做摘要。
public actor ContextSummarizer {
    private let modelRouter: ModelRouter?
    private let provider: ModelProvider

    public init(modelRouter: ModelRouter? = nil, provider: ModelProvider = .deepseek) {
        self.modelRouter = modelRouter
        self.provider = provider
    }

    /// 将多轮对话摘要为简短描述
    public func summarize(messages: [Message], maxTokens: Int = 200) async -> String? {
        guard !messages.isEmpty else { return nil }

        // 尝试 Apple Intelligence（macOS 26+）
        if #available(macOS 26, *) {
            if let localSummary = await localSummary(messages: messages) {
                return localSummary
            }
        }

        // 降级：LLM API 调用
        guard let router = modelRouter else { return nil }

        let context = messages.map { "\($0.role.rawValue): \($0.content.prefix(300))" }.joined(separator: "\n")
        let prompt = "请用1-2句中文简要总结以下对话的核心内容：\n\n\(context)"

        let request = ChatRequest(
            model: provider.defaultModel,
            messages: [Message(role: .user, content: prompt)],
            maxTokens: maxTokens
        )

        do {
            let stream = try await router.chat(request, provider: provider)
            var summary = ""
            for try await chunk in stream {
                if case .text(let t) = chunk { summary += t }
            }
            return summary.isEmpty ? nil : summary.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    @available(macOS 26, *)
    private func localSummary(messages: [Message]) async -> String? {
        // Apple FoundationModels MLSummarizer 占位
        // 需要 import FoundationModels (macOS 26+)
        return nil
    }
}
