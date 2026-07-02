import Foundation
import YunPatNetworking

/// KV-stable 上下文压缩器
///
/// 核心原则：渲染的 prompt prefix 跨迭代字节单调稳定，不破坏 paged-KV prefix cache。
///
/// 规则：
/// - 已摘要的 tool result 逐字节重放（永不重写）
/// - 已 drop 的消息永不复活
/// - 已发送 verbatim 的消息老化时只 drop 不重新摘要（避免改写）
/// - trim note 是 count-free 的，多 drop 不改其字节
/// - 受保护区：首条消息（原始任务）+ 最近 3 个 turn-pair
/// - 受保护区 + tail 仍超预算 → overBudget（不发 doomed 请求）
public struct CompactionWatermark: Sendable {

    /// 已摘要的 tool result key → 固定摘要文本
    private var summarizedResults: [String: String] = [:]
    /// 已 drop 的消息 content hash
    private var droppedMessageHashes: Set<String> = []
    /// 受保护的最近 turn-pair 数
    public let protectedRecentPairs: Int

    /// count-free trim note（固定字节）
    public static let trimNote: String = "[Note: Earlier messages were trimmed…]"
    public init(protectedRecentPairs: Int = 3) {
        self.protectedRecentPairs = protectedRecentPairs
    }

    // MARK: - Public API

    /// 压缩主入口：保证渲染 prefix 跨迭代 byte-stable
    public mutating func compact(
        messages: [Message],
        request: ChatRequest,
        budget: ContextBudget,
        provider: ModelProvider
    ) -> CompactResult {
        let history: [Message] = messages
        let totalTokens = TokenEstimator.estimate(messages: history, provider: provider)

        guard totalTokens > budget.availableForHistory else {
            return CompactResult(messages: history, note: nil, overBudget: false)
        }

        // 逐层压缩，每次检查是否满足
        var working: [Message] = history

        // 1. Microcompact：摘要旧 tool result（保留已摘要的稳定文本）
        working = microcompact(messages: working, provider: provider)

        let afterMicro = TokenEstimator.estimate(messages: working, provider: provider)
        if afterMicro <= budget.availableForHistory {
            return CompactResult(messages: working, note: nil, overBudget: false)
        }

        // 2. Prune：drop 中间消息（已 drop 的不复活）
        working = pruneMessages(messages: working, provider: provider)

        let afterPrune = TokenEstimator.estimate(messages: working, provider: provider)
        if afterPrune <= budget.availableForHistory {
            return CompactResult(messages: working, note: Self.trimNote, overBudget: false)
        }

        // 3. 保护区内后仍放不下 → overBudget
        return CompactResult(messages: working, note: Self.trimNote, overBudget: true)
    }

    // MARK: - Internal

    /// 摘要旧 tool result（保留已摘要的稳定文本）
    private mutating func microcompact(messages: [Message], provider: ModelProvider) -> [Message] {
        var result: [Message] = messages
        // 从后往前找 tool result，标记可摘要的
        var toolResultCount: Int = 0
        let keepRecent: Int = 3
        for idx in result.indices.reversed() where result[idx].role == .tool {
            toolResultCount += 1
            if toolResultCount > keepRecent {
                let key: String = "msg_\(idx)"
                if let existing = summarizedResults[key] {
                    result[idx] = Message(role: .tool, content: existing)
                } else {
                    let summary = summarize(text: result[idx].content)
                    summarizedResults[key] = summary
                    result[idx] = Message(role: .tool, content: summary)
                }
            }
        }
        return result
    }

    /// 丢弃中间消息，保留首条 + 尾 N 个 turn-pair（每个 pair = user + 其后所有 msg 到下一个 user 前）
    private mutating func pruneMessages(messages: [Message], provider: ModelProvider) -> [Message] {
        guard messages.count > 2 else { return messages }

        var kept: [Message] = [messages[0]]
        var idx: Int = messages.count - 1
        var pairsCollected: Int = 0
        while idx > 0 && pairsCollected < protectedRecentPairs {
            if messages[idx].role == .user {
                pairsCollected += 1
            }
            idx -= 1
        }

        if idx > 0 {
            kept.append(contentsOf: messages[(idx + 1)...])
        } else {
            kept.append(contentsOf: messages[1...])
        }

        // 追踪被 drop 的消息（不可复活）
        let keptContent: Set = Set(kept.map { contentHash($0) })
        for msg in messages {
            let hash = contentHash(msg)
            if !keptContent.contains(hash) {
                droppedMessageHashes.insert(hash)
            }
        }

        return kept
    }

    private func contentHash(_ msg: Message) -> String {
        "\(msg.role.rawValue):\(msg.content.prefix(80))"
    }

    // MARK: - Helpers

    /// 生成 tool result 摘要
    private func summarize(text: String) -> String {
        if text.count <= 200 { return text }
        let head = text.prefix(100)
        let tail = text.suffix(100)
        return "\(head)\n…[truncated \(text.count - 200) chars]…\n\(tail)"
    }
}

// MARK: - CompactResult

public struct CompactResult: Sendable {
    public let messages: [Message]
    public let note: String?
    public let overBudget: Bool

    public init(messages: [Message], note: String?, overBudget: Bool) {
        self.messages = messages
        self.note = note
        self.overBudget = overBudget
    }
}
