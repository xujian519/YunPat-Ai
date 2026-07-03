import Foundation

// MARK: - Tool Call State

/// 对标 Tokio `sync/oneshot.rs` 的 `State(usize)` 位标志状态机
///
/// 使用 `OptionSet` 位标志表示工具调用的生命周期状态，
/// 支持组合状态（如 `executing | awaitingUser`）。
///
/// ## 设计参考
///
/// Tokio oneshot 用单个 `AtomicUsize` 编码：
/// - `RX_TASK_SET` (bit 0) — 接收端 waker 已设置
/// - `VALUE_SENT`  (bit 1) — 值已发送
/// - `CLOSED`       (bit 2) — 通道关闭
/// - `TX_TASK_SET`  (bit 3) — 发送端 waker 已设置
///
/// 这里对应到工具调用生命周期：
/// - `queued` → 已入队，等待调度
/// - `executing` → 正在执行（可同时 `awaitingUser`）
/// - `awaitingUser` → 等待用户确认（可与 `executing` 共存）
/// - `completed` / `failed` / `cancelled` → 终态（互斥）
/// - `retrying` → 失败后重试中
public struct ToolCallState: OptionSet, Sendable, CustomStringConvertible {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    // ── 核心状态位 ──

    /// 空闲（零状态）
    public static let idle: ToolCallState = ToolCallState([])
    /// 已入队，等待调度
    public static let queued: ToolCallState = ToolCallState(rawValue: 1 << 0)
    /// 正在执行
    public static let executing: ToolCallState = ToolCallState(rawValue: 1 << 1)
    /// 等待用户确认（可与 executing 共存）
    public static let awaitingUser: ToolCallState = ToolCallState(rawValue: 1 << 2)
    /// 执行成功
    public static let completed: ToolCallState = ToolCallState(rawValue: 1 << 3)
    /// 执行失败
    public static let failed: ToolCallState = ToolCallState(rawValue: 1 << 4)
    /// 已取消
    public static let cancelled: ToolCallState = ToolCallState(rawValue: 1 << 5)
    /// 失败后重试中
    public static let retrying: ToolCallState = ToolCallState(rawValue: 1 << 6)
    // ── 组合 ──

    /// 终态集合
    public static let terminal: ToolCallState = [.completed, .failed, .cancelled]

    /// 活跃状态（正在执行或重试中）
    public static let active: ToolCallState = [.executing, .retrying]

    // ── 查询 ──

    /// 是否为终态
    public var isTerminal: Bool { !isDisjoint(with: Self.terminal) }

    /// 是否正在活跃执行
    public var isActive: Bool { !isDisjoint(with: Self.active) }

    /// 是否空闲
    public var isIdle: Bool { rawValue == 0 }

    /// 是否可取消（非终态都可取消）
    public var isCancellable: Bool { !isTerminal }

    // ── 转换验证 ──

    /// 验证从当前状态到目标状态的转换是否合法
    /// - Returns: nil 表示合法，否则返回非法原因描述
    public func validateTransition(to target: ToolCallState) -> String? {
        // 从终态不能转换到任何其他状态
        if isTerminal && target != self {
            return "Cannot transition from terminal state '\(description)' to '\(target.description)'"
        }
        // 从 idle 只能到 queued
        if isIdle && target != .queued {
            return "Cannot transition from idle directly to '\(target.description)'"
        }
        // 已完成不能转到失败
        if contains(.completed) && target.contains(.failed) {
            return "Cannot transition from completed to failed"
        }
        return nil
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        var parts: [String] = []
        if contains(.queued) { parts.append("queued") }
        if contains(.executing) { parts.append("executing") }
        if contains(.awaitingUser) { parts.append("awaiting_user") }
        if contains(.completed) { parts.append("completed") }
        if contains(.failed) { parts.append("failed") }
        if contains(.cancelled) { parts.append("cancelled") }
        if contains(.retrying) { parts.append("retrying") }
        return parts.isEmpty ? "idle" : parts.joined(separator: "|")
    }
}

// MARK: - Tool Call Record

/// 单次工具调用的完整生命周期记录
///
/// 对标 Tokio metrics：每次工具调用都产生一个记录，
/// 包含状态变迁时间戳，可用于延迟分析和性能调优。
public struct ToolCallRecord: Identifiable, Sendable {
    public let id: UUID
    public let toolName: String
    /// JSON-encodable input (use JSONValue or primitive types for Sendable safety)
    public let input: JSONValue?
    public var state: ToolCallState
    public var output: String?
    public var errorMessage: String?
    public let createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        toolName: String,
        input: JSONValue? = nil,
        state: ToolCallState = .queued
    ) {
        self.id = id
        self.toolName = toolName
        self.input = input
        self.state = state
        self.createdAt = Date()
    }

    /// 开始执行
    public func start() -> ToolCallRecord {
        var copy: ToolCallRecord = self
        copy.state = .executing
        copy.startedAt = Date()
        return copy
    }

    /// 等待用户确认
    public func awaitUser() -> ToolCallRecord {
        var copy: ToolCallRecord = self
        copy.state.insert(.awaitingUser)
        return copy
    }

    /// 执行完成
    public func complete(output: String) -> ToolCallRecord {
        var copy: ToolCallRecord = self
        copy.state = [.completed]
        copy.output = output
        copy.completedAt = Date()
        return copy
    }

    /// 执行失败
    public func fail(error: Error) -> ToolCallRecord {
        var copy: ToolCallRecord = self
        copy.state = [.failed]
        copy.errorMessage = error.localizedDescription
        copy.completedAt = Date()
        return copy
    }

    /// 取消
    public func cancel() -> ToolCallRecord {
        var copy: ToolCallRecord = self
        copy.state = [.cancelled]
        copy.completedAt = Date()
        return copy
    }

    /// 执行耗时（毫秒）
    public var durationMs: Double? {
        guard let start = startedAt, let end = completedAt else { return nil }
        return end.timeIntervalSince(start) * 1000
    }
}
