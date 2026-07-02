import Foundation

// MARK: - AgentEvent

/// Agent 运行时事件枚举 — 工具执行/任务开始/完成/预算超限/错误等
public enum AgentEvent: Sendable {
    case toolPreExecute(toolName: String, callId: String)
    case toolDenied(toolName: String, reason: String)
    case toolPostExecute(toolName: String, success: Bool)
    case taskStarted(prompt: String)
    case taskCompleted(summary: String)
    case budgetExceeded(limit: Int, actual: Int)
    case errorOccurred(message: String)
}

// MARK: - PreExecutionDecision

/// 工具执行前的拦截决策 — 在权限检查之后由 preExecutionGate 返回
///
/// - `.allow` — 正常执行
/// - `.deny(reason)` — 跳过执行，reason 作为工具结果喂回 model
public enum PreExecutionDecision: Sendable {
    case allow
    case deny(String)
}

// MARK: - EventBus

/// 轻量事件总线 — 跨组件 pub/sub
///
/// 用途：
/// - UI 层订阅事件更新界面（工具执行状态、成本告警）
/// - 日志/审计层订阅事件记录
/// - 诊断层订阅事件分析性能
///
/// 不用于控制流（控制流用 `PreExecutionDecision` / `InterceptAction`）。
public actor EventBus {
    public static let shared: EventBus = EventBus()

    private var subscribers: [UUID: @Sendable (AgentEvent) async -> Void] = [:]

    public init() {}

    /// 订阅事件，返回 subscription ID（可用于取消订阅）
    @discardableResult
    public func subscribe(_ handler: @Sendable @escaping (AgentEvent) async -> Void) -> UUID {
        let id: UUID = UUID()
        subscribers[id] = handler
        return id
    }

    /// 取消指定 ID 的订阅
    public func unsubscribe(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    /// 取消所有订阅
    public func unsubscribeAll() {
        subscribers.removeAll()
    }

    /// 发布事件通知所有订阅者
    public func publish(_ event: AgentEvent) async {
        for handler in subscribers.values {
            await handler(event)
        }
    }

    /// 当前订阅者数量
    public var subscriberCount: Int { subscribers.count }
}
