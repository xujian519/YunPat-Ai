import Foundation

// MARK: - Layer 1: WorkingMemory (iteration lifetime)
/// Active reasoning state within a single loop iteration.
/// Never persisted — cleared between iterations.
public struct WorkingMemory: Sendable, Codable {
    public var currentGoal: String
    public var activeHypotheses: [String]
    public var scratchpad: [String]
    public var intermediateResults: [String: String]

    public init(
        currentGoal: String = "",
        activeHypotheses: [String] = [],
        scratchpad: [String] = [],
        intermediateResults: [String: String] = [:]
    ) {
        self.currentGoal = currentGoal
        self.activeHypotheses = activeHypotheses
        self.scratchpad = scratchpad
        self.intermediateResults = intermediateResults
    }
}

// MARK: - Layer 2: SessionFact (session lifetime)
public struct SessionFact: Sendable, Codable {
    public let id: UUID
    public let fact: String
    public let category: FactCategory
    public let timestamp: Date

    public init(fact: String, category: FactCategory = .other) {
        self.id = UUID()
        self.fact = fact
        self.category = category
        self.timestamp = Date()
    }
}

public enum FactCategory: String, Sendable, Codable {
    case technicalFeature
    case legalRule
    case decision
    case strategy
    case other
}

// MARK: - Layer 3: CaseContext (case lifetime)
/// Per-patent-case context — persisted per caseId.
public struct CaseContext: Sendable, Codable {
    public let caseId: String
    public var applicationNumber: String?
    public var technicalField: String
    public var inventionPoints: [String]
    public var keyReferences: [String]
    public var openIssues: [String]
    public var lastModified: Date

    public init(
        caseId: String = UUID().uuidString,
        applicationNumber: String? = nil,
        technicalField: String = "",
        inventionPoints: [String] = [],
        keyReferences: [String] = [],
        openIssues: [String] = []
    ) {
        self.caseId = caseId
        self.applicationNumber = applicationNumber
        self.technicalField = technicalField
        self.inventionPoints = inventionPoints
        self.keyReferences = keyReferences
        self.openIssues = openIssues
        self.lastModified = Date()
    }
}

// MARK: - Layer 4: LongTermMemory (cross-case lifetime)
/// Accumulated knowledge across cases — legal precedents,
/// successful argument patterns, learned domain refinements.
public struct LongTermMemory: Sendable, Codable {
    public var legalPrecedents: [String]
    public var successfulStrategies: [String]
    public var domainVocabulary: [String: String]
    public var learnedPitfalls: [String]
    public var lastConsolidated: Date
    public var items: [MemoryItem]

    public init(
        legalPrecedents: [String] = [],
        successfulStrategies: [String] = [],
        domainVocabulary: [String: String] = [:],
        learnedPitfalls: [String] = [],
        lastConsolidated: Date = Date(),
        items: [MemoryItem] = []
    ) {
        self.legalPrecedents = legalPrecedents
        self.successfulStrategies = successfulStrategies
        self.domainVocabulary = domainVocabulary
        self.learnedPitfalls = learnedPitfalls
        self.lastConsolidated = lastConsolidated
        self.items = items
    }
}

public struct MemoryItem: Sendable, Codable {
    public let id: UUID
    public let content: String
    public var salience: Float
    public let createdAt: Date

    public init(id: UUID = UUID(), content: String, salience: Float = 0.5, createdAt: Date = Date()) {
        self.id = id
        self.content = content
        self.salience = salience
        self.createdAt = createdAt
    }
}

public struct Episode: Sendable, Codable {
    public let id: UUID
    public let topics: [String]
    public let entities: [String]
    public let decisions: [String]
    public let salience: Float
    public let summary: String
    public let createdAt: Date

    public init(id: UUID = UUID(), topics: [String] = [], entities: [String] = [], decisions: [String] = [],
                salience: Float = 0.5, summary: String = "", createdAt: Date = Date()) {
        self.id = id
        self.topics = topics
        self.entities = entities
        self.decisions = decisions
        self.salience = salience
        self.summary = summary
        self.createdAt = createdAt
    }
}

public struct LTMItem: Sendable, Codable {
    public let id: UUID
    public let content: String
    public let source: String
    public let salience: Float
    public let createdAt: Date

    public init(
        id: UUID = UUID(), content: String, source: String = "",
        salience: Float = 0.5, createdAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.source = source
        self.salience = salience
        self.createdAt = createdAt
    }
}

public struct PinnedFact: Sendable, Codable {
    public let id: UUID
    public let fact: String
    public let salience: Float
    public let sourceCount: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(), fact: String,
        salience: Float = 0.5, sourceCount: Int = 1, createdAt: Date = Date()
    ) {
        self.id = id
        self.fact = fact
        self.salience = salience
        self.sourceCount = sourceCount
        self.createdAt = createdAt
    }
}

public enum ToolDependencyTier: String, Codable, Sendable {
    case tier0
    case tier1
    case tier2
    case tier3
}

// MARK: - Layer 5: GlobalMemory (user preferences lifetime)
/// Cross-session user preferences — writing style, terminology, providers.
public struct GlobalMemory: Sendable, Codable {
    public var writingStyle: String
    public var terminologyPreferences: [String: String]
    public var preferredProviders: [String]

    public init(
        writingStyle: String = "",
        terminologyPreferences: [String: String] = [:],
        preferredProviders: [String] = []
    ) {
        self.writingStyle = writingStyle
        self.terminologyPreferences = terminologyPreferences
        self.preferredProviders = preferredProviders
    }
}
