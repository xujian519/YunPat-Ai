import Foundation

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

public protocol AgentHook: Sendable {
    var point: HookPoint { get }
    func execute(context: HookContext) async throws
}

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

public actor HookChain {
    private var hooks: [any AgentHook] = []

    public func register(_ hook: any AgentHook) {
        hooks.append(hook)
    }

    public func execute(point: HookPoint, context: HookContext) async {
        for hook in hooks where hook.point == point {
            try? await hook.execute(context: context)
        }
    }
}
