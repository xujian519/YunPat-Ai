import Foundation
import YunPatNetworking

/// 全量压缩器 — 调用 LLM 将消息列表摘要为紧凑表示
///
/// 用于 CompactionWatermark Level 3（FullCompact），
/// 将除首条用户消息外的整个对话压缩为一条 system 消息。
/// 一旦摘要被缓存（在 CompactionWatermark 中），后续迭代不变，保证 KV 稳定。
public actor FullCompactor {
    private let summarizer: ContextSummarizer
    private let maxSummaryTokens: Int

    public init(summarizer: ContextSummarizer, maxSummaryTokens: Int = 300) {
        self.summarizer = summarizer
        self.maxSummaryTokens = maxSummaryTokens
    }

    /// 压缩消息列表为一条摘要消息
    /// - Parameter messages: 待压缩的消息（不含首条保护消息）
    /// - Returns: 包含摘要的 system 消息，压缩失败返回 nil
    public func compact(_ messages: [Message]) async -> Message? {
        guard !messages.isEmpty else { return nil }

        let summary: String = await summarizer.summarize(
            messages: messages,
            maxTokens: maxSummaryTokens
        ) ?? fallbackCompact(messages)

        return Message(
            role: .system,
            content: "【上下文摘要】\n\(summary)"
        )
    }

    /// 降级方案：当 LLM 摘要失败时使用截断拼接
    private func fallbackCompact(_ messages: [Message]) -> String {
        let total: Int = messages.count
        let head: String = messages.prefix(2).map { "\($0.role.rawValue): \($0.content.prefix(100))" }
            .joined(separator: "\n")
        let tail: String = messages.suffix(2).map { "\($0.role.rawValue): \($0.content.prefix(100))" }
            .joined(separator: "\n")
        return "对话共 \(total) 轮。开头: \(head)\n…\n结尾: \(tail)"
    }
}
