import Foundation

public protocol ReasoningStrategy: Sendable {
    var name: String { get }
    func execute(context: ReasoningContext) async throws -> ReasoningOutput
}

public struct ReasoningContext: Sendable {
    public let userRequest: UserRequest
    public let blackboard: FactBlackboard
    public let rules: ApplicableRules

    public init(userRequest: UserRequest, blackboard: FactBlackboard, rules: ApplicableRules) {
        self.userRequest = userRequest
        self.blackboard = blackboard
        self.rules = rules
    }
}

public struct ReasoningOutput: Sendable {
    public let result: String
    public let metadata: [String: String]

    public init(result: String, metadata: [String: String] = [:]) {
        self.result = result
        self.metadata = metadata
    }
}

public struct ReactStrategy: ReasoningStrategy {
    public let name: String = "react"

    public func execute(context: ReasoningContext) async throws -> ReasoningOutput {
        ReasoningOutput(result: "React 推理完成")
    }
}

public struct SixStepStrategy: ReasoningStrategy {
    public let name: String = "six_step"

    public func execute(context: ReasoningContext) async throws -> ReasoningOutput {
        ReasoningOutput(result: "六步推理完成", metadata: ["steps": "6"])
    }
}

public struct ChainOfThoughtStrategy: ReasoningStrategy {
    public let name: String = "chain_of_thought"

    public func execute(context: ReasoningContext) async throws -> ReasoningOutput {
        ReasoningOutput(result: "思维链推理完成")
    }
}

public struct KgReasoningStrategy: ReasoningStrategy {
    public let name: String = "kg_reasoning"

    public func execute(context: ReasoningContext) async throws -> ReasoningOutput {
        let chains: [ReasoningChain] = await context.blackboard.reasoningChains
        let summary = chains.map { "\($0.from) → \($0.toNode)" }.joined(separator: "; ")
        return ReasoningOutput(result: "KG推理: \(summary)", metadata: ["chains": "\(chains.count)"])
    }
}

public actor StrategyRegistry {
    private var strategies: [String: any ReasoningStrategy] = [:]

    public func register(_ strategy: any ReasoningStrategy) {
        strategies[strategy.name] = strategy
    }

    public func strategy(named name: String) -> (any ReasoningStrategy)? {
        strategies[name]
    }

    public func allStrategies() -> [String] {
        Array(strategies.keys)
    }

    public func registerDefaults() {
        register(ReactStrategy())
        register(SixStepStrategy())
        register(ChainOfThoughtStrategy())
        register(KgReasoningStrategy())
    }
}
