import Foundation

// MARK: - Layer 1: WorkingMemory (iteration lifetime)
/// Layer 1: 工作记忆 — 单次循环迭代内的活跃推理状态，从不持久化
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
/// Layer 2: 会话事实 — 当前 session 内短期事实，含分类和时间戳
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

/// 事实分类 — technicalFeature / legalRule / decision / strategy / other
public enum FactCategory: String, Sendable, Codable {
    case technicalFeature
    case legalRule
    case decision
    case strategy
    case other
}

// MARK: - Layer 3: CaseContext (case lifetime)
/// Layer 3: 案件上下文 — 按 caseId 持久化的案件信息，案件结束后归档
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
/// Layer 4: 长期记忆 — 跨案件累积的知识（法理先例、成功策略、陷阱教训）
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

/// 记忆条目 — LTM 中的基本单位，包含内容和显著性评分
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

/// 事件片段 — 记录一次推理或交互的有意义片段，含话题、实体和决策
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

/// LTM 条目 — 带来源和显著性评分的长期知识片段
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

/// 固定事实 — 被多次确认的核心事实，显著性高不会被遗忘
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

/// 工具依赖层级 — T0~T3 用于分档测试和 CI 调度
public enum ToolDependencyTier: String, Codable, Sendable {
    case tier0
    case tier1
    case tier2
    case tier3
}

// MARK: - Layer 5: GlobalMemory (user preferences lifetime)
/// Layer 5: 全局记忆 — 跨 session 持久化的用户偏好（写作风格、术语偏好、首选提供商）
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
