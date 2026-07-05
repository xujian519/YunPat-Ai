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

public struct RuleConstraint: Sendable, Codable {
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

public enum ConstraintLevel: String, Sendable, Codable {
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

public struct FactConflict: Sendable, Identifiable {
    public let id: String
    public let field: String
    public let oldValue: String
    public let newValue: String
    public var resolved: Bool

    public init(field: String, oldValue: String, newValue: String) {
        self.id = UUID().uuidString
        self.field = field
        self.oldValue = oldValue
        self.newValue = newValue
        self.resolved = false
    }
}

public actor FactBlackboard {
    private var _technicalField: String = ""
    private var _problem: String = ""
    private var _inventionPoints: [String] = []
    private var _missingInfo: [String] = []

    private var _reasoningChains: [ReasoningChain] = []
    private var _ruleConstraints: [RuleConstraint] = []
    private var _articleJudgments: [ArticleJudgment] = []
    private var _executionPlan: ExecutionPlan?

    private var _factsLocked: Bool = false
    private var _conflicts: [FactConflict] = []

    public init() {}

    public var technicalField: String { _technicalField }
    public var problem: String { _problem }
    public var inventionPoints: [String] { _inventionPoints }
    public var missingInfo: [String] { _missingInfo }
    public var reasoningChains: [ReasoningChain] { _reasoningChains }
    public var ruleConstraints: [RuleConstraint] { _ruleConstraints }
    public var articleJudgments: [ArticleJudgment] { _articleJudgments }
    public var executionPlan: ExecutionPlan? { _executionPlan }
    public var isFactsLocked: Bool { _factsLocked }
    public var conflicts: [FactConflict] { _conflicts }
    public var unresolvedConflicts: [FactConflict] { _conflicts.filter { !$0.resolved } }

    @discardableResult
    public func writeFacts(
        technicalField: String, problem: String, inventionPoints: [String], missingInfo: [String] = [],
        force: Bool = false
    ) -> Bool {
        if _factsLocked && !force { return false }

        if !_technicalField.isEmpty && technicalField != _technicalField {
            _conflicts.append(
                FactConflict(field: "technicalField", oldValue: _technicalField, newValue: technicalField)
            )
        }
        if !_problem.isEmpty && problem != _problem {
            _conflicts.append(FactConflict(field: "problem", oldValue: _problem, newValue: problem))
        }

        _technicalField = technicalField
        _problem = problem
        _inventionPoints = inventionPoints
        _missingInfo = missingInfo
        return true
    }

    @discardableResult
    public func updateTechnicalField(_ value: String, force: Bool = false) -> Bool {
        if _factsLocked && !force { return false }
        if !_technicalField.isEmpty && value != _technicalField {
            _conflicts.append(FactConflict(field: "technicalField", oldValue: _technicalField, newValue: value))
        }
        _technicalField = value
        return true
    }

    @discardableResult
    public func updateProblem(_ value: String, force: Bool = false) -> Bool {
        if _factsLocked && !force { return false }
        if !_problem.isEmpty && value != _problem {
            _conflicts.append(FactConflict(field: "problem", oldValue: _problem, newValue: value))
        }
        _problem = value
        return true
    }

    @discardableResult
    public func addInventionPoint(_ point: String, force: Bool = false) -> Bool {
        if _factsLocked && !force { return false }
        if !_inventionPoints.contains(point) {
            _inventionPoints.append(point)
        }
        return true
    }

    @discardableResult
    public func addMissingInfo(_ info: String, force: Bool = false) -> Bool {
        if _factsLocked && !force { return false }
        if !_missingInfo.contains(info) {
            _missingInfo.append(info)
        }
        return true
    }

    public func writeReasoningResults(chains: [ReasoningChain], constraints: [RuleConstraint]) {
        _reasoningChains = chains
        _ruleConstraints = constraints
    }

    public func appendReasoningChain(_ chain: ReasoningChain) {
        if !_reasoningChains.contains(where: { $0.from == chain.from && $0.toNode == chain.toNode }) {
            _reasoningChains.append(chain)
        }
    }

    public func writeArticleJudgments(_ judgments: [ArticleJudgment]) {
        _articleJudgments = judgments
    }

    public func appendArticleJudgment(_ judgment: ArticleJudgment) {
        if let idx = _articleJudgments.firstIndex(where: { $0.articleId == judgment.articleId }) {
            _articleJudgments[idx] = judgment
        } else {
            _articleJudgments.append(judgment)
        }
    }

    public func writeExecutionPlan(_ plan: ExecutionPlan) {
        _executionPlan = plan
    }

    public func lockFacts() {
        _factsLocked = true
    }

    public func unlockFacts() {
        _factsLocked = false
    }

    public func resolveConflict(id: String, useNewValue: Bool) {
        guard let idx = _conflicts.firstIndex(where: { $0.id == id }) else { return }
        _conflicts[idx].resolved = true
        if useNewValue {
            switch _conflicts[idx].field {
            case "technicalField":
                _technicalField = _conflicts[idx].newValue
            case "problem":
                _problem = _conflicts[idx].newValue
            default:
                break
            }
        }
    }

    public func clearResolvedConflicts() {
        _conflicts.removeAll { $0.resolved }
    }

    public func toStructuredFacts() -> StructuredFacts {
        StructuredFacts(
            technicalField: _technicalField,
            problem: _problem,
            inventionPoints: _inventionPoints,
            missingInfo: _missingInfo)
    }
}
