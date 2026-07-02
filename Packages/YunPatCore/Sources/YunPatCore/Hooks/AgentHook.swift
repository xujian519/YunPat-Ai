import Foundation

/// Hook 触发点枚举 — 定义在 Agent 执行流程的哪些阶段触发 Hook
public enum HookPoint: String, Sendable {
    case preToolCall
    case postToolCall
    case onError
    case prePlanning
    case postPlanning
    case preExecution
    case postExecution
    case onComplete
}

/// Agent Hook 协议 — 在特定 HookPoint 注入自定义逻辑，扩展 Agent 行为
public protocol AgentHook: Sendable {
    var point: HookPoint { get }
    func execute(context: HookContext) async throws
}

/// Hook 执行上下文 — 携带工具名、错误信息和事实黑板供 Hook 使用
public struct HookContext: Sendable {
    public let toolName: String?
    public let error: Error?
    public let blackboard: FactBlackboard?

    public init(
        toolName: String? = nil,
        error: Error? = nil,
        blackboard: FactBlackboard? = nil
    ) {
        self.toolName = toolName
        self.error = error
        self.blackboard = blackboard
    }
}

/// Hook 链 — 管理注册的 AgentHook，在指定点顺序执行
public actor HookChain {
    private var hooks: [any AgentHook] = []

    /// 注册一个 Hook 到链中
    public func register(_ hook: any AgentHook) {
        hooks.append(hook)
    }

    /// 在指定点执行所有匹配的 Hook
    public func execute(point: HookPoint, context: HookContext) async {
        for hook in hooks where hook.point == point {
            try? await hook.execute(context: context)
        }
    }
}
