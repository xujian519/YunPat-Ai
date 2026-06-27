import Foundation
import YunPatNetworking

public actor PatentLoopEngine: LoopEngine {
    public var state: LoopState = .idle
    private let modelRouter: ModelRouter
    private let provider: ModelProvider
    private let wikiAdapter: WikiAdapter
    private let ruleEngine: RuleEngine
    private let factExtractor: FactExtractor
    private let contextEngine: ContextEngine
    private let innerLoop: AgentLoopEngine
    private let evaluator: EvaluationEngine
    private let config: LoopConfig

    public init(modelRouter: ModelRouter, wikiAdapter: WikiAdapter, provider: ModelProvider = .deepseek, config: LoopConfig = LoopConfig()) {
        self.modelRouter = modelRouter
        self.wikiAdapter = wikiAdapter
        self.provider = provider
        self.ruleEngine = RuleEngine(adapter: wikiAdapter)
        self.factExtractor = FactExtractor()
        self.contextEngine = ContextEngine()
        self.innerLoop = AgentLoopEngine(modelRouter: modelRouter, provider: provider)
        self.evaluator = EvaluationEngine()
        self.config = config
    }

    public func run(request: UserRequest, flow: AgentFlow) async throws -> LoopResult {
        var revisionCount = 0
        state = .running(step: "extracting-facts")
        let facts = await factExtractor.extract(from: request)
        if !facts.missingInfo.isEmpty, flow == .guided {
            return .needsClarification(facts.missingInfo)
        }

        state = .running(step: "retrieving-rules")
        let rules = try await ruleEngine.retrieveRules(for: facts)

        while revisionCount < config.maxRevisionCycles {
            state = .running(step: "planning")
            _ = ExecutionPlan(
                strategy: "基于\(rules.candidates.count)条规则制定策略",
                steps: [PlanStep(name: "执行", description: "根据规则分析事实", boundRule: rules.candidates.first?.wikilink)]
            )

            state = .running(step: "executing")
            let contextPrompt = "技术领域：\(facts.technicalField)\n问题：\(facts.problem)\n发明点：\(facts.inventionPoints.joined(separator: "; "))\n\n\(rules.injectableTokens(maxTokens: 2000))"
            let execReq = UserRequest(content: contextPrompt)
            let execResult = try await innerLoop.run(request: execReq, flow: .fullAgent)
            let artifacts: [String] = {
                if case .completed(let t) = execResult { return [t] }
                return []
            }()
            let result = ExecutionResult(stepResults: [StepResult(stepName: "execute", output: artifacts.first ?? "")], artifacts: artifacts)

            state = .running(step: "reviewing")
            let review = await evaluator.evaluate(execution: result, rules: rules, facts: facts)
            if review.verdict {
                state = .idle
                return .completed(artifacts.joined(separator: "\n\n"))
            }
            revisionCount += 1
        }
        state = .idle
        return .exceededRevisionLimit([Issue(description: "超过最大修订次数 \(config.maxRevisionCycles)")])
    }
}
