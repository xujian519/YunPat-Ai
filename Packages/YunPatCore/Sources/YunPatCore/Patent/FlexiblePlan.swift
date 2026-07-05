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

    // MARK: - Execution

    public var currentStage: PlanStage? {
        stages.first { $0.status == .inProgress }
    }

    public var nextPendingStage: PlanStage? {
        stages.first { $0.status == .pending }
    }

    public var isComplete: Bool {
        !stages.isEmpty && stages.allSatisfy { $0.status == .completed || $0.status == .skipped }
    }

    public struct PlanProgress: Sendable {
        public let completed: Int
        public let inProgress: Int
        public let pending: Int
        public let skipped: Int
        public let total: Int
        public var ratio: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    public var progress: PlanProgress {
        PlanProgress(
            completed: stages.filter { $0.status == .completed }.count,
            inProgress: stages.filter { $0.status == .inProgress }.count,
            pending: stages.filter { $0.status == .pending }.count,
            skipped: stages.filter { $0.status == .skipped }.count,
            total: stages.count
        )
    }

    @discardableResult
    public func advance() -> PlanStage? {
        if let inProgressIdx = stages.firstIndex(where: { $0.status == .inProgress }) {
            stages[inProgressIdx].status = .completed
        }
        if let pendingIdx = stages.firstIndex(where: { $0.status == .pending }) {
            stages[pendingIdx].status = .inProgress
            return stages[pendingIdx]
        }
        return nil
    }

    public func skipCurrent() {
        if let idx = stages.firstIndex(where: { $0.status == .inProgress }) {
            stages[idx].status = .skipped
        }
    }

    public func reset() {
        for idx in stages.indices {
            stages[idx].status = .pending
        }
    }

    // MARK: - Persistence

    private struct PlanSnapshot: Codable {
        let stages: [PlanStage]
        let constraints: [RuleConstraint]
    }

    public func save(to url: URL) throws {
        let snapshot = PlanSnapshot(stages: stages, constraints: _constraints)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    public func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(PlanSnapshot.self, from: data)
        stages = snapshot.stages
        _constraints = snapshot.constraints
    }
}
