import Foundation

// MARK: - Stage Pattern

public struct StagePattern: Sendable, Codable {
    public struct Stage: Sendable, Codable {
        public let name: String
        public let goal: String
        public let toolSequence: [String]

        public init(name: String, goal: String, toolSequence: [String] = []) {
            self.name = name
            self.goal = goal
            self.toolSequence = toolSequence
        }
    }

    public let caseType: CaseType
    public let technicalField: String
    public let stages: [Stage]
    public var frequency: Int
    public var lastUsed: Date

    public init(
        caseType: CaseType,
        technicalField: String,
        stages: [Stage],
        frequency: Int = 1,
        lastUsed: Date = Date()
    ) {
        self.caseType = caseType
        self.technicalField = technicalField
        self.stages = stages
        self.frequency = frequency
        self.lastUsed = lastUsed
    }

    public mutating func recordUse() {
        frequency += 1
        lastUsed = Date()
    }
}

// MARK: - Case Reflection

public struct CaseReflection: Sendable, Codable {
    public let caseId: String
    public let caseType: CaseType
    public let technicalField: String
    public let outcome: String
    public let effectiveStrategies: [String]
    public let mistakes: [String]
    public let lessonsLearned: String

    public init(
        caseId: String,
        caseType: CaseType,
        technicalField: String,
        outcome: String,
        effectiveStrategies: [String] = [],
        mistakes: [String] = [],
        lessonsLearned: String = ""
    ) {
        self.caseId = caseId
        self.caseType = caseType
        self.technicalField = technicalField
        self.outcome = outcome
        self.effectiveStrategies = effectiveStrategies
        self.mistakes = mistakes
        self.lessonsLearned = lessonsLearned
    }
}

// MARK: - Pattern Learner Actor

public actor PatternLearner {

    private var patterns: [StagePattern] = []
    private var reflections: [String: CaseReflection] = [:]

    public init() {}

    /// Record a new pattern or update frequency of an existing one.
    /// - Returns: The recorded (or updated) pattern.
    @discardableResult
    public func learn(
        caseType: CaseType,
        technicalField: String,
        stages: [StagePattern.Stage],
        toolSequence: [String]
    ) -> StagePattern {
        if let index = patterns.firstIndex(where: {
            $0.caseType == caseType && $0.technicalField == technicalField
        }) {
            var existing: StagePattern = patterns[index]
            existing.recordUse()
            patterns[index] = existing
            return existing
        }

        let newPattern: StagePattern = StagePattern(
            caseType: caseType,
            technicalField: technicalField,
            stages: stages,
            frequency: 1,
            lastUsed: Date()
        )
        patterns.append(newPattern)
        return newPattern
    }

    /// Find the most similar pattern by matching caseType exactly
    /// and technicalField by prefix, returning the highest-frequency match.
    public func suggestStages(
        caseType: CaseType,
        technicalField: String
    ) -> StagePattern? {
        let candidates: [StagePattern] =
            patterns
            .filter { $0.caseType == caseType }
            .sorted { first, second in
                let firstMatch =
                    technicalField.hasPrefix(first.technicalField)
                    || first.technicalField.hasPrefix(technicalField)
                let secondMatch =
                    technicalField.hasPrefix(second.technicalField)
                    || second.technicalField.hasPrefix(technicalField)
                if firstMatch != secondMatch { return firstMatch }
                return first.frequency > second.frequency
            }

        return candidates.first
    }

    /// Store a reflection for a completed case.
    public func reflect(caseId: String, reflection: CaseReflection) {
        reflections[caseId] = reflection
    }

    /// Retrieve the top N patterns for a given case type, sorted by frequency.
    public func topPatterns(caseType: CaseType, limit: Int) -> [StagePattern] {
        patterns
            .filter { $0.caseType == caseType }
            .sorted { $0.frequency > $1.frequency }
            .prefix(max(0, limit))
            .map { $0 }
    }

    /// Return all stored reflections.
    public func allReflections() -> [CaseReflection] {
        Array(reflections.values)
    }

    /// Look up a reflection by case ID.
    public func reflection(for caseId: String) -> CaseReflection? {
        reflections[caseId]
    }
}
