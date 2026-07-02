import Foundation

public struct PlanStage: Sendable, Identifiable, Codable {
    public let id: String
    public var name: String
    public var description: String
    public var status: StageStatus
    public var attachedArticles: [String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String = "",
        status: StageStatus = .pending,
        attachedArticles: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.status = status
        self.attachedArticles = attachedArticles
    }
}

public enum StageStatus: String, Sendable, Codable {
    case pending
    case inProgress
    case completed
    case skipped
}

public actor FlexiblePlan {
    private var stages: [PlanStage] = []
    private var _constraints: [RuleConstraint] = []

    public var currentStages: [PlanStage] { stages }
    public var constraints: [RuleConstraint] { _constraints }

    public func setStages(_ newStages: [PlanStage]) {
        stages = newStages
    }

    public func addStage(_ stage: PlanStage) {
        stages.append(stage)
    }

    public func removeStage(_ id: String) {
        stages.removeAll { $0.id == id }
    }

    public func reorder(from: Int, destination: Int) {
        guard stages.indices.contains(from), stages.indices.contains(destination) else { return }
        let stage = stages.remove(at: from)
        stages.insert(stage, at: destination)
    }

    public func markStage(_ id: String, status: StageStatus) {
        guard let index = stages.firstIndex(where: { $0.id == id }) else { return }
        stages[index].status = status
    }

    public func setConstraints(_ constraints: [RuleConstraint]) {
        _constraints = constraints
    }
}
