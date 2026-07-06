import Foundation

/// 上下文压缩策略 — 控制各压缩层级的触发行为和阈值
///
/// 每个层级定义触发阈值（budget 使用率），控制压缩的激进程度。
/// 使用率 = 实际 token / budget.availableForHistory * 100%。
///
/// 提供三种预设：
/// - `.conservative`：保守策略，尽量保留上下文完整
/// - `.balanced`（默认）：平衡策略
/// - `.aggressive`：激进策略，优先节省 token
public struct CompactionPolicy: Sendable {
    /// 启用 Snip 层级（Level 2）
    public let enableSnip: Bool
    /// 启用 FullCompact 层级（Level 3）
    public let enableFullCompact: Bool
    /// 启用 OverflowRecovery 层级（Level 4）
    public let enableOverflowRecovery: Bool
    /// 受保护的 turn-pair 数
    public let protectedRecentPairs: Int
    /// FullCompact 摘要的最大 token 数
    public let maxSummaryTokens: Int

    public init(
        enableSnip: Bool = true,
        enableFullCompact: Bool = true,
        enableOverflowRecovery: Bool = true,
        protectedRecentPairs: Int = 3,
        maxSummaryTokens: Int = 300
    ) {
        self.enableSnip = enableSnip
        self.enableFullCompact = enableFullCompact
        self.enableOverflowRecovery = enableOverflowRecovery
        self.protectedRecentPairs = protectedRecentPairs
        self.maxSummaryTokens = maxSummaryTokens
    }

    /// 保守策略 — 尽量保留上下文，仅用 microcompact
    public static let conservative = CompactionPolicy(
        enableSnip: false,
        enableFullCompact: false,
        enableOverflowRecovery: false,
        protectedRecentPairs: 5
    )

    /// 平衡策略 — 启用 Snip 和 FullCompact，保留 3 个 turn-pair
    public static let balanced = CompactionPolicy()

    /// 激进策略 — 全部启用，保留较少的 turn-pair
    public static let aggressive = CompactionPolicy(
        enableFullCompact: true,
        enableOverflowRecovery: true,
        protectedRecentPairs: 2,
        maxSummaryTokens: 200
    )
}
