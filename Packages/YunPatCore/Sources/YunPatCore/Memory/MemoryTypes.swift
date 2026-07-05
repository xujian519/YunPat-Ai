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

// MARK: - Audit Types

/// 记忆来源类型 — 用于白盒记忆审计
public enum MemorySource: String, Sendable, Codable {
    case sessionFact
    case writePathDistillation
    case manualEdit
    case consolidation
    case importFile
}

/// 记忆层级 — 对应五层记忆架构
public enum MemoryLayer: String, Sendable, Codable {
    case working
    case session
    case caseContext
    case longTerm
    case global
}

/// 可审计记忆条目 — 跨五层记忆的统一视图
///
/// 注意：避免与 `LLMMemoryStore.MemoryEntry`（YAML markdown 条目）混淆；
/// 本类型用于记忆审计与 CaseContext/LongTermMemory 内部数据。
public struct AuditableMemoryEntry: Identifiable, Sendable, Codable {
    public let id: UUID
    public let layer: MemoryLayer
    public let caseId: String?
    public var content: String
    public var source: MemorySource
    public let sourceTurn: Int?
    public let toolCall: String?
    public var confidence: Float
    public var isPinned: Bool
    public var isArchived: Bool
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        layer: MemoryLayer,
        caseId: String? = nil,
        content: String,
        source: MemorySource = .sessionFact,
        sourceTurn: Int? = nil,
        toolCall: String? = nil,
        confidence: Float = 0.5,
        isPinned: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.layer = layer
        self.caseId = caseId
        self.content = content
        self.source = source
        self.sourceTurn = sourceTurn
        self.toolCall = toolCall
        self.confidence = confidence
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
    }
}

// MARK: - Layer 3: CaseContext (case lifetime)

/// Layer 3: 案件上下文 — 按 caseId 持久化的案件信息，案件结束后归档
public struct CaseContext: Sendable, Codable {
    public let caseId: String
    public var applicationNumber: String?
    public var technicalFieldEntry: AuditableMemoryEntry?
    public var inventionPointEntries: [AuditableMemoryEntry]
    public var keyReferenceEntries: [AuditableMemoryEntry]
    public var openIssueEntries: [AuditableMemoryEntry]
    public var lastModified: Date

    /// 兼容旧字段：读取时自动从 String 数组迁移到 MemoryEntry
    public var technicalField: String {
        get { technicalFieldEntry?.content ?? "" }
        set {
            technicalFieldEntry = AuditableMemoryEntry(
                layer: .caseContext,
                caseId: caseId,
                content: newValue,
                source: technicalFieldEntry?.source ?? .sessionFact
            )
        }
    }

    public var inventionPoints: [String] {
        get { inventionPointEntries.map(\.content) }
        set {
            inventionPointEntries = newValue.map { content in
                AuditableMemoryEntry(layer: .caseContext, caseId: caseId, content: content, source: .sessionFact)
            }
        }
    }

    public var keyReferences: [String] {
        get { keyReferenceEntries.map(\.content) }
        set {
            keyReferenceEntries = newValue.map { content in
                AuditableMemoryEntry(layer: .caseContext, caseId: caseId, content: content, source: .sessionFact)
            }
        }
    }

    public var openIssues: [String] {
        get { openIssueEntries.map(\.content) }
        set {
            openIssueEntries = newValue.map { content in
                AuditableMemoryEntry(layer: .caseContext, caseId: caseId, content: content, source: .sessionFact)
            }
        }
    }

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
        self.technicalFieldEntry = technicalField.isEmpty
            ? nil
            : AuditableMemoryEntry(layer: .caseContext, caseId: caseId, content: technicalField, source: .sessionFact)
        self.inventionPointEntries = inventionPoints.map {
            AuditableMemoryEntry(layer: .caseContext, caseId: caseId, content: $0, source: .sessionFact)
        }
        self.keyReferenceEntries = keyReferences.map {
            AuditableMemoryEntry(layer: .caseContext, caseId: caseId, content: $0, source: .sessionFact)
        }
        self.openIssueEntries = openIssues.map {
            AuditableMemoryEntry(layer: .caseContext, caseId: caseId, content: $0, source: .sessionFact)
        }
        self.lastModified = Date()
    }

    enum CodingKeys: String, CodingKey {
        case caseId
        case applicationNumber
        case technicalFieldEntry
        case inventionPointEntries
        case keyReferenceEntries
        case openIssueEntries
        case lastModified
        case technicalField
        case inventionPoints
        case keyReferences
        case openIssues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let caseId = try container.decode(String.self, forKey: .caseId)
        self.caseId = caseId
        self.applicationNumber = try container.decodeIfPresent(String.self, forKey: .applicationNumber)
        self.lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified) ?? Date()

        if let entry = try container.decodeIfPresent(AuditableMemoryEntry.self, forKey: .technicalFieldEntry) {
            self.technicalFieldEntry = entry
        } else {
            let legacy = try container.decodeIfPresent(String.self, forKey: .technicalField) ?? ""
            self.technicalFieldEntry = legacy.isEmpty
                ? nil
                : AuditableMemoryEntry(layer: .caseContext, caseId: caseId, content: legacy, source: .sessionFact)
        }

        if let entries = try container.decodeIfPresent([AuditableMemoryEntry].self, forKey: .inventionPointEntries) {
            self.inventionPointEntries = entries
        } else {
            let legacy = try container.decodeIfPresent([String].self, forKey: .inventionPoints) ?? []
            self.inventionPointEntries = legacy.map {
                AuditableMemoryEntry(layer: .caseContext, caseId: caseId, content: $0, source: .sessionFact)
            }
        }

        if let entries = try container.decodeIfPresent([AuditableMemoryEntry].self, forKey: .keyReferenceEntries) {
            self.keyReferenceEntries = entries
        } else {
            let legacy = try container.decodeIfPresent([String].self, forKey: .keyReferences) ?? []
            self.keyReferenceEntries = legacy.map {
                AuditableMemoryEntry(layer: .caseContext, caseId: caseId, content: $0, source: .sessionFact)
            }
        }

        if let entries = try container.decodeIfPresent([AuditableMemoryEntry].self, forKey: .openIssueEntries) {
            self.openIssueEntries = entries
        } else {
            let legacy = try container.decodeIfPresent([String].self, forKey: .openIssues) ?? []
            self.openIssueEntries = legacy.map {
                AuditableMemoryEntry(layer: .caseContext, caseId: caseId, content: $0, source: .sessionFact)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(caseId, forKey: .caseId)
        try container.encodeIfPresent(applicationNumber, forKey: .applicationNumber)
        try container.encode(technicalFieldEntry, forKey: .technicalFieldEntry)
        try container.encode(inventionPointEntries, forKey: .inventionPointEntries)
        try container.encode(keyReferenceEntries, forKey: .keyReferenceEntries)
        try container.encode(openIssueEntries, forKey: .openIssueEntries)
        try container.encode(lastModified, forKey: .lastModified)
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

/// 长期记忆条目 — 扩展 MemoryItem 支持审计字段
public struct MemoryItem: Identifiable, Sendable, Codable {
    public let id: UUID
    public var content: String
    public var salience: Float
    public let source: MemorySource
    public let sourceTurn: Int?
    public let toolCall: String?
    public var confidence: Float
    public var isPinned: Bool
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        content: String,
        salience: Float = 0.5,
        source: MemorySource = .consolidation,
        sourceTurn: Int? = nil,
        toolCall: String? = nil,
        confidence: Float = 0.5,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.salience = salience
        self.source = source
        self.sourceTurn = sourceTurn
        self.toolCall = toolCall
        self.confidence = confidence
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
    }
}

public extension MemoryItem {
    /// 转换为跨层统一的审计条目
    func asMemoryEntry(layer: MemoryLayer = .longTerm, caseId: String? = nil) -> AuditableMemoryEntry {
        AuditableMemoryEntry(
            id: id,
            layer: layer,
            caseId: caseId,
            content: content,
            source: source,
            sourceTurn: sourceTurn,
            toolCall: toolCall,
            confidence: confidence,
            isPinned: isPinned,
            isArchived: false,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }

    /// 从审计条目重建
    init(from entry: AuditableMemoryEntry, salience: Float = 0.5) {
        self.id = entry.id
        self.content = entry.content
        self.salience = salience
        self.source = entry.source
        self.sourceTurn = entry.sourceTurn
        self.toolCall = entry.toolCall
        self.confidence = entry.confidence
        self.isPinned = entry.isPinned
        self.createdAt = entry.createdAt
        self.modifiedAt = entry.modifiedAt
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
/// 全局记忆 — 跨 session 持久化的用户偏好（写作风格、术语偏好、首选提供商）
public struct GlobalMemory: Sendable, Codable {
    public var writingStyleEntry: AuditableMemoryEntry?
    public var terminologyPreferences: [String: String]
    public var preferredProviders: [String]

    /// 兼容旧字段
    public var writingStyle: String {
        get { writingStyleEntry?.content ?? "" }
        set {
            writingStyleEntry = newValue.isEmpty
                ? nil
                : AuditableMemoryEntry(layer: .global, content: newValue, source: .manualEdit)
        }
    }

    public init(
        writingStyle: String = "",
        terminologyPreferences: [String: String] = [:],
        preferredProviders: [String] = []
    ) {
        self.writingStyleEntry = writingStyle.isEmpty
            ? nil
            : AuditableMemoryEntry(layer: .global, content: writingStyle, source: .manualEdit)
        self.terminologyPreferences = terminologyPreferences
        self.preferredProviders = preferredProviders
    }

    enum CodingKeys: String, CodingKey {
        case writingStyleEntry
        case terminologyPreferences
        case preferredProviders
        case writingStyle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.terminologyPreferences = try container.decodeIfPresent(
            [String: String].self,
            forKey: .terminologyPreferences
        ) ?? [:]
        self.preferredProviders = try container.decodeIfPresent([String].self, forKey: .preferredProviders) ?? []

        if let entry = try container.decodeIfPresent(AuditableMemoryEntry.self, forKey: .writingStyleEntry) {
            self.writingStyleEntry = entry
        } else {
            let legacy = try container.decodeIfPresent(String.self, forKey: .writingStyle) ?? ""
            self.writingStyleEntry = legacy.isEmpty
                ? nil
                : AuditableMemoryEntry(layer: .global, content: legacy, source: .manualEdit)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(writingStyleEntry, forKey: .writingStyleEntry)
        try container.encode(terminologyPreferences, forKey: .terminologyPreferences)
        try container.encode(preferredProviders, forKey: .preferredProviders)
    }
}
