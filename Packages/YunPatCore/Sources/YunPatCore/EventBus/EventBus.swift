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

// MARK: - HandlerResult

/// Handler 执行结果 — completed 或 timed out
public enum HandlerResult: Sendable {
    case completed
    case timedOut
}

// MARK: - Subscriber Entry

private final class SubscriberEntry: @unchecked Sendable {
    let id: UUID
    let handler: @Sendable (AgentEvent) async -> Void

    init(id: UUID, handler: @escaping @Sendable (AgentEvent) async -> Void) {
        self.id = id
        self.handler = handler
    }
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
///
/// 并发散播：使用 withTaskGroup 并发通知所有订阅者，
/// 每个 handler 有 30s 超时保护，防止慢 handler 阻塞整体。
/// 弱引用存储避免 handler 闭包捕获 self 导致内存泄漏。
public actor EventBus {
    public static let shared: EventBus = EventBus()

    private var entries: [SubscriberEntry] = []
    private let handlerTimeoutSeconds: Double = 30

    public init() {}

    /// 订阅事件，返回 subscription ID（可用于取消订阅）
    @discardableResult
    public func subscribe(_ handler: @Sendable @escaping (AgentEvent) async -> Void) -> UUID {
        let id: UUID = UUID()
        entries.append(SubscriberEntry(id: id, handler: handler))
        return id
    }

    /// 取消指定 ID 的订阅
    public func unsubscribe(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// 取消所有订阅
    public func unsubscribeAll() {
        entries.removeAll()
    }

    /// 发布事件通知所有订阅者（并发散播 + 超时保护）
    public func publish(_ event: AgentEvent) async {
        let snapshot: [SubscriberEntry] = entries

        await withTaskGroup(of: HandlerResult.self) { group in
            for entry in snapshot {
                let handler: @Sendable (AgentEvent) async -> Void = entry.handler
                group.addTask {
                    await withTaskGroup(of: HandlerResult.self) { inner in
                        inner.addTask {
                            await handler(event)
                            return .completed
                        }
                        inner.addTask {
                            try? await Task.sleep(nanoseconds: UInt64(30 * 1_000_000_000))
                            return .timedOut
                        }
                        return await inner.next() ?? .completed
                    }
                }
            }

            for await result in group {
                if case .timedOut = result {
                    print("[EventBus] Handler timed out after \(self.handlerTimeoutSeconds)s")
                }
            }
        }
    }

    /// 当前订阅者数量
    public var subscriberCount: Int { entries.count }
}
