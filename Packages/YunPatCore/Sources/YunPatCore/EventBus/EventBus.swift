import Foundation

// MARK: - AgentEvent

/// Agent 运行时事件 — 供 EventBus 广播
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

/// 工具执行前的拦截决策
///
/// 在工具执行前（权限检查之后）由 `preExecutionGate` 返回。
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

    @discardableResult
    public func subscribe(_ handler: @Sendable @escaping (AgentEvent) async -> Void) -> UUID {
        let id: UUID = UUID()
        subscribers[id] = handler
        return id
    }

    public func unsubscribe(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    public func unsubscribeAll() {
        subscribers.removeAll()
    }

    public func publish(_ event: AgentEvent) async {
        for handler in subscribers.values {
            await handler(event)
        }
    }

    public var subscriberCount: Int { subscribers.count }
}
