import Foundation
import YunPatNetworking

/// KV-stable 多层上下文压缩器
///
/// 核心原则：渲染的 prompt prefix 跨迭代字节单调稳定，不破坏 paged-KV prefix cache。
///
/// 规则：
/// - 已摘要的 tool result 逐字节重放（永不重写）
/// - 已 drop 的消息永不复活
/// - 已发送 verbatim 的消息老化时只 drop 不重新摘要（避免改写）
/// - trim note 是 count-free 的，多 drop 不改其字节
/// - 受保护区：首条消息（原始任务）+ 最近 N 个 turn-pair
///
/// 压缩层级（逐层尝试，每层更激进）：
/// - Level 0: 无操作，budget 充足
/// - Level 1: MicroCompact — 摘要旧 tool result，保留最近 N 个原始结果
/// - Level 2: Snip — 保留首条 + 尾 N 个 turn-pair，中间整体替换为 trim note
/// - Level 3: FullCompact — LLM 摘要压缩整个对话（除首条）
/// - Level 4: OverflowRecovery — 仅保留最近 2 个 turn-pair + 当前请求
/// - Level 5: OverBudget — 窗口放不下
public final class CompactionWatermark: @unchecked Sendable {

    /// 已摘要的 tool result key → 固定摘要文本
    private var summarizedResults: [String: String] = [:]
    /// 已 drop 的消息 content hash
    private var droppedMessageHashes: Set<String> = []
    /// 受保护的最近 turn-pair 数
    public let protectedRecentPairs: Int

    // ── Token 估算缓存（增量优化，避免 O(n²)） ──
    /// 缓存的完整消息数组 token 估算值
    private var cachedTokenCount: Int?
    /// 上次调用 compact 时的消息数量
    private var lastMessageCount: Int = 0

    // ── Snip 稳定切点 ──
    /// 上次 snip 的切点 index，保持 KV 稳定
    private var snipCutIndex: Int?

    // ── 全量压缩缓存 ──
    /// 已产生的全量压缩摘要文本（LLM 生成后固定）
    private var fullCompactText: String?

    /// count-free trim note（固定字节）
    public static let trimNote: String = "[Note: Earlier messages were trimmed…]"
    public init(protectedRecentPairs: Int = 3) {
        self.protectedRecentPairs = protectedRecentPairs
    }

    // MARK: - Public API

    /// 多层压缩主入口：保证渲染 prefix 跨迭代 byte-stable
    ///
    /// 从 Level 0 开始逐层尝试更激进的压缩，每层成功后检查预算。
    /// `fullCompactor` 为可选参数，仅在开启 FullCompact 层级时需要。
    public func compact(
        messages: [Message],
        request: ChatRequest,
        budget: ContextBudget,
        provider: ModelProvider,
        fullCompactor: FullCompactor? = nil
    ) async -> CompactResult {
        let history: [Message] = messages
        let totalTokens: Int = computeTokenCount(messages: history, provider: provider)

        cachedTokenCount = totalTokens
        lastMessageCount = messages.count

        // Level 0: 已满足预算，无操作
        guard totalTokens > budget.availableForHistory else {
            return CompactResult(messages: history, note: nil, overBudget: false, level: 0)
        }

        var working: [Message] = history

        // Level 1: MicroCompact — 摘要旧 tool result（保留已摘要的稳定文本）
        working = microcompact(messages: working, provider: provider)
        if fitsBudget(working, budget, provider) {
            return CompactResult(messages: working, note: nil, overBudget: false, level: 1)
        }

        // Level 2: Snip — 保留首条 + 尾 N 个 turn-pair，中间替换为 trim note
        working = snip(messages: working)
        if fitsBudget(working, budget, provider) {
            return CompactResult(messages: working, note: Self.trimNote, overBudget: false, level: 2)
        }

        // Level 3: FullCompact — LLM 摘要压缩（全量）
        if let compactor = fullCompactor {
            working = await fullCompact(messages: working, compactor: compactor)
            if fitsBudget(working, budget, provider) {
                return CompactResult(messages: working, note: Self.trimNote, overBudget: false, level: 3)
            }
        }

        // Level 4: OverflowRecovery — 仅保留最近 2 个 turn-pair
        working = overflowRecovery(messages: working)
        if fitsBudget(working, budget, provider) {
            return CompactResult(messages: working, note: Self.trimNote, overBudget: false, level: 4)
        }

        // Level 5: OverBudget
        return CompactResult(messages: working, note: Self.trimNote, overBudget: true, level: 5)
    }

    // MARK: - Internal

    /// 逐字节稳定的 tool result 摘要（保留已摘要的稳定文本）
    private func microcompact(messages: [Message], provider: ModelProvider) -> [Message] {
        var result: [Message] = messages
        var toolResultCount: Int = 0
        let keepRecent: Int = 3
        for idx in result.indices.reversed() where result[idx].role == .tool {
            toolResultCount += 1
            if toolResultCount > keepRecent {
                let key: String = "tool_\(contentHash(result[idx]))"
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

    /// Snip：保留首条 + 尾 N 个 turn-pair，中间整体替换为 trim note
    ///
    /// 比 prune 更激进：中间丢弃的消息用一个 system 消息代替（而非静默删除），
    /// 且切点一旦固定不再移动（`snipCutIndex` 缓存），保证 KV 稳定。
    private func snip(messages: [Message]) -> [Message] {
        guard messages.count > 2 else { return messages }

        let cutAt: Int
        if let stable = snipCutIndex, stable < messages.count {
            cutAt = min(stable, messages.count - 1)
        } else {
            cutAt = findSnipCut(messages: messages)
            snipCutIndex = cutAt
        }

        // 只保留首条 + 尾部 content
        var kept: [Message] = [messages[0]]
        if cutAt > 0 {
            kept.append(contentsOf: messages[cutAt...])
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

    /// 计算稳定的 snip 切点：从尾向前数 protectedRecentPairs 个 user 消息
    private func findSnipCut(messages: [Message]) -> Int {
        var idx: Int = messages.count - 1
        var pairsCollected: Int = 0
        while idx > 0 && pairsCollected < protectedRecentPairs {
            if messages[idx].role == .user {
                pairsCollected += 1
            }
            if pairsCollected < protectedRecentPairs {
                idx -= 1
            }
        }
        // 如果尾部的 turn-pair 不足，保护所有
        if pairsCollected < protectedRecentPairs { return 1 }
        // 如果切点覆盖全部，至少保留一条
        return max(1, idx)
    }

    /// FullCompact：将整个对话（除首条）替换为 LLM 生成的摘要
    /// 同一 `fullCompactText` 被缓存后不再变更，保证 KV 稳定
    private func fullCompact(messages: [Message], compactor: FullCompactor) async -> [Message] {
        guard messages.count > 1 else { return messages }

        if let cached = fullCompactText {
            return [messages[0], Message(role: .system, content: cached)]
        }

        let summaryMessages: [Message] = Array(messages[1...])
        guard let summary = await compactor.compact(summaryMessages) else {
            return messages
        }

        fullCompactText = summary.content
        return [messages[0], summary]
    }

    /// OverflowRecovery：仅保留最近 2 个 turn-pair + 首条
    private func overflowRecovery(messages: [Message]) -> [Message] {
        guard messages.count > 2 else { return messages }

        // 临时调低保护对数到 2 执行激进裁剪
        var kept: [Message] = [messages[0]]
        var idx: Int = messages.count - 1
        var pairsCollected: Int = 0
        while idx > 0 && pairsCollected < 2 {
            if messages[idx].role == .user {
                pairsCollected += 1
            }
            if pairsCollected < 2 {
                idx -= 1
            }
        }
        if pairsCollected < 2 {
            kept = Array(messages.suffix(min(3, messages.count)))
        } else if idx > 0 {
            kept.append(contentsOf: messages[idx...])
        }

        let keptContent: Set = Set(kept.map { contentHash($0) })
        for msg in messages {
            let hash = contentHash(msg)
            if !keptContent.contains(hash) {
                droppedMessageHashes.insert(hash)
            }
        }

        return kept
    }

    // MARK: - Helpers

    /// 检查压缩后的消息是否满足预算
    private func fitsBudget(_ messages: [Message], _ budget: ContextBudget, _ provider: ModelProvider) -> Bool {
        TokenEstimator.estimate(messages: messages, provider: provider) <= budget.availableForHistory
    }

    /// Token 计数（含增量缓存优化）
    private func computeTokenCount(messages: [Message], provider: ModelProvider) -> Int {
        if messages.count == lastMessageCount, let cached = cachedTokenCount {
            return cached
        } else if messages.count > lastMessageCount, let cached = cachedTokenCount {
            let newCount: Int = messages.count - lastMessageCount
            let newMessages = messages.suffix(newCount)
            let addedTokens = TokenEstimator.estimate(messages: Array(newMessages), provider: provider)
            return cached + addedTokens
        } else {
            return TokenEstimator.estimate(messages: messages, provider: provider)
        }
    }

    private func contentHash(_ msg: Message) -> String {
        "\(msg.role.rawValue):\(msg.content.hashValue)"
    }

    /// 生成 tool result 摘要
    private func summarize(text: String) -> String {
        if text.count <= 200 { return text }
        let head = text.prefix(100)
        let tail = text.suffix(100)
        return "\(head)\n…[truncated \(text.count - 200) chars]…\n\(tail)"
    }
}

// MARK: - CompactResult

/// 压缩结果 — 包含压缩后的消息、note、预算状态和已应用的压缩层级
public struct CompactResult: Sendable {
    public let messages: [Message]
    public let note: String?
    public let overBudget: Bool
    /// 应用的压缩层级（0=无操作，1=micro, 2=snip, 3=full, 4=overflow, 5=overBudget）
    public let level: Int

    public init(messages: [Message], note: String?, overBudget: Bool, level: Int = 0) {
        self.messages = messages
        self.note = note
        self.overBudget = overBudget
        self.level = level
    }
}
