import Foundation

// MARK: - Cooperative Scheduler

/// 对标 Tokio `task/coop` 的协作调度器
///
/// 每次工具调用 / LLM 推理前调用 `proceed()`，预算耗尽时主动 `Task.yield()`，
/// 防止 Agent 循环长期霸占 actor 线程导致 UI 卡顿和其他标签饥饿。
///
/// ## 设计参考
///
/// Tokio `task/coop/mod.rs`：
/// - `Budget(Option<u8>)` → `remaining: Int`, `inUnconstrained: Bool`
/// - `poll_proceed()` → `proceed() async`
/// - `unconstrained()` → `unconstrained(_:) async`
///
/// ## 使用方式
///
/// ```swift
/// let coop = CoopScheduler(budget: 128)
/// for _ in 0..<1000 {
///     await coop.proceed()  // 每 128 次自动 yield
///     // ... 工具调用
/// }
/// ```
public actor CoopScheduler {
    private let budgetLimit: Int
    private var remaining: Int
    private var inUnconstrained: Bool = false

    /// 已执行的 yield 次数（指标）
    public private(set) var yieldCount: Int = 0

    public init(budget: Int = 128) {
        self.budgetLimit = budget
        self.remaining = budget
    }

    /// 消耗 1 单位预算。耗尽时主动 yield 并重置。
    ///
    /// Agent 循环每次迭代开始时调用。不阻塞，只在实际耗尽时 yield。
    public func proceed() async {
        guard !inUnconstrained else { return }
        remaining &-= 1
        if remaining <= 0 {
            remaining = budgetLimit
            yieldCount += 1
            await Task.yield()
        }
    }

    /// 不消耗预算执行关键路径操作
    ///
    /// 对标 Tokio `coop::unconstrained()`，用于超时检查、中断检测等
    /// 不应被协作调度打断的路径。
    public func unconstrained<T: Sendable>(_ work: @Sendable () async -> T) async -> T {
        inUnconstrained = true
        defer { inUnconstrained = false }
        return await work()
    }

    /// 是否还有预算剩余
    public var hasBudgetRemaining: Bool {
        remaining > 0 || inUnconstrained
    }

    /// 剩余预算（用于调试）
    public var budgetRemaining: Int { remaining }

    /// 重置为满预算
    public func reset() {
        remaining = budgetLimit
    }
}
