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

// MARK: - Persisted Store

private struct PatternLearnerStore: Codable {
    let patterns: [StagePattern]
    let reflections: [CaseReflection]
}

// MARK: - Pattern Learner Actor

public actor PatternLearner {

    private var patterns: [StagePattern] = []
    private var reflections: [String: CaseReflection] = [:]
    private let storeURL: URL
    private var loaded: Bool = false

    public init(storeURL: URL? = nil) {
        if let url = storeURL {
            self.storeURL = url
        } else {
            let appSupport: URL = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.storeURL = appSupport
                .appendingPathComponent("YunPatAI", isDirectory: true)
                .appendingPathComponent("pattern-learner.json")
        }
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let data: Data = try? Data(contentsOf: storeURL) else { return }
        let decoder: JSONDecoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let store: PatternLearnerStore = try? decoder.decode(
            PatternLearnerStore.self, from: data
        ) else { return }
        patterns = store.patterns
        for reflection in store.reflections {
            reflections[reflection.caseId] = reflection
        }
    }

    private func saveToDisk() {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let store: PatternLearnerStore = PatternLearnerStore(
            patterns: patterns,
            reflections: Array(reflections.values)
        )

        guard let data: Data = try? encoder.encode(store) else { return }
        let dirURL: URL = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        try? data.write(to: storeURL, options: [.atomic])
    }

    // MARK: - Learning

    @discardableResult
    public func learn(
        caseType: CaseType,
        technicalField: String,
        stages: [StagePattern.Stage],
        toolSequence: [String]
    ) -> StagePattern {
        ensureLoaded()
        if let index: Int = patterns.firstIndex(where: {
            $0.caseType == caseType && $0.technicalField == technicalField
        }) {
            var existing: StagePattern = patterns[index]
            existing.recordUse()
            patterns[index] = existing
            saveToDisk()
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
        saveToDisk()
        return newPattern
    }

    // MARK: - Suggestion

    public func suggestStages(
        caseType: CaseType,
        technicalField: String
    ) -> StagePattern? {
        ensureLoaded()
        let candidates: [StagePattern] = patterns
            .filter { $0.caseType == caseType }
            .sorted { first, second in
                let firstMatch: Bool =
                    technicalField.hasPrefix(first.technicalField)
                    || first.technicalField.hasPrefix(technicalField)
                let secondMatch: Bool =
                    technicalField.hasPrefix(second.technicalField)
                    || second.technicalField.hasPrefix(technicalField)
                if firstMatch != secondMatch { return firstMatch }
                return first.frequency > second.frequency
            }

        return candidates.first
    }

    // MARK: - Reflection

    public func reflect(caseId: String, reflection: CaseReflection) {
        ensureLoaded()
        reflections[caseId] = reflection
        saveToDisk()
    }

    // MARK: - Querying

    public func topPatterns(caseType: CaseType, limit: Int) -> [StagePattern] {
        ensureLoaded()
        return patterns
            .filter { $0.caseType == caseType }
            .sorted { $0.frequency > $1.frequency }
            .prefix(max(0, limit))
            .map { $0 }
    }

    public func allReflections() -> [CaseReflection] {
        ensureLoaded()
        return Array(reflections.values)
    }

    public func reflection(for caseId: String) -> CaseReflection? {
        ensureLoaded()
        return reflections[caseId]
    }
}
