import Foundation

public struct ReasoningChain: Sendable {
    public let from: String
    public let toNode: String
    public let evidence: String
    public init(from: String, toNode: String, evidence: String) {
        self.from = from
        self.toNode = toNode
        self.evidence = evidence
    }
}

public struct RuleConstraint: Sendable {
    public let articleId: String
    public let articleName: String
    public let requirement: ConstraintLevel
    public let description: String
    public let applicableStages: [String]
    public init(
        articleId: String, articleName: String, requirement: ConstraintLevel, description: String,
        applicableStages: [String]
    ) {
        self.articleId = articleId
        self.articleName = articleName
        self.requirement = requirement
        self.description = description
        self.applicableStages = applicableStages
    }
}

public enum ConstraintLevel: String, Sendable {
    case must
    case should
    case note
}

public struct ArticleJudgment: Sendable {
    public let articleId: String
    public let articleName: String
    public let conclusion: String
    public let reasoning: String
    public init(articleId: String, articleName: String, conclusion: String, reasoning: String) {
        self.articleId = articleId
        self.articleName = articleName
        self.conclusion = conclusion
        self.reasoning = reasoning
    }
}

public final class FactBlackboard: @unchecked Sendable {
    private let lock = NSLock()

    private var _technicalField: String = ""
    private var _problem: String = ""
    private var _inventionPoints: [String] = []
    private var _missingInfo: [String] = []

    private var _reasoningChains: [ReasoningChain] = []
    private var _ruleConstraints: [RuleConstraint] = []
    private var _articleJudgments: [ArticleJudgment] = []
    private var _executionPlan: ExecutionPlan?

    private var _factsLocked: Bool = false

    public init() {}

    public var technicalField: String { lock.withLock { _technicalField } }
    public var problem: String { lock.withLock { _problem } }
    public var inventionPoints: [String] { lock.withLock { _inventionPoints } }
    public var missingInfo: [String] { lock.withLock { _missingInfo } }
    public var reasoningChains: [ReasoningChain] { lock.withLock { _reasoningChains } }
    public var ruleConstraints: [RuleConstraint] { lock.withLock { _ruleConstraints } }
    public var articleJudgments: [ArticleJudgment] { lock.withLock { _articleJudgments } }
    public var executionPlan: ExecutionPlan? { lock.withLock { _executionPlan } }
    public var isFactsLocked: Bool { lock.withLock { _factsLocked } }

    public func writeFacts(
        technicalField: String, problem: String, inventionPoints: [String], missingInfo: [String] = []
    ) {
        lock.withLock {
            _technicalField = technicalField
            _problem = problem
            _inventionPoints = inventionPoints
            _missingInfo = missingInfo
        }
    }

    public func writeReasoningResults(chains: [ReasoningChain], constraints: [RuleConstraint]) {
        lock.withLock {
            _reasoningChains = chains
            _ruleConstraints = constraints
        }
    }

    public func writeArticleJudgments(_ judgments: [ArticleJudgment]) {
        lock.withLock { _articleJudgments = judgments }
    }

    public func writeExecutionPlan(_ plan: ExecutionPlan) {
        lock.withLock { _executionPlan = plan }
    }

    public func lockFacts() {
        lock.withLock { _factsLocked = true }
    }

    public func toStructuredFacts() -> StructuredFacts {
        lock.withLock {
            StructuredFacts(
                technicalField: _technicalField,
                problem: _problem,
                inventionPoints: _inventionPoints,
                missingInfo: _missingInfo)
        }
    }
}
