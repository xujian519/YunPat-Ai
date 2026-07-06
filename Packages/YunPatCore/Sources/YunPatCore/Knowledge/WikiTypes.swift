import Foundation

/// 知识库模块枚举 — 对应 Wiki 知识库中的不同领域模块
public enum WikiModule: String, CaseIterable, Sendable {
    case patentPractice = "专利实务"
    case examinationGuide = "审查指南"
    case patentInfringement = "专利侵权"
    case patentJudgments = "专利判决"
    case reexamination = "复审无效"
    case laws = "法律法规"
    case books = "书籍"
}

/// 从用户请求中提取的结构化事实 — 包含技术领域、问题、发明点、缺失信息等
public struct StructuredFacts: Sendable {
    public let technicalField: String
    public let problem: String
    public let inventionPoints: [String]
    public let missingInfo: [String]
    public let sourceDocument: URL?
    public let caseReferences: [String]
    public init(
        technicalField: String = "", problem: String = "", inventionPoints: [String] = [], missingInfo: [String] = [],
        sourceDocument: URL? = nil, caseReferences: [String] = []
    ) {
        self.technicalField = technicalField
        self.problem = problem
        self.inventionPoints = inventionPoints
        self.missingInfo = missingInfo
        self.sourceDocument = sourceDocument
        self.caseReferences = caseReferences
    }
}

/// 规则来源类型 — 法律条文 / 审查指南 / 判例 / 判决 / 学术 / 自定义
public enum RuleSource: Sendable {
    case statute(String)
    case guideline(String)
    case precedent(String)
    case judgment(String)
    case doctrine
}

/// 证据链接 — 指向规则的原始来源及其摘录
public struct EvidenceLink: Sendable {
    public let source: RuleSource
    public let wikilink: String
    public let excerpt: String
    public init(source: RuleSource, wikilink: String, excerpt: String) {
        self.source = source
        self.wikilink = wikilink
        self.excerpt = excerpt
    }
}

/// 规则冲突性质 — 覆盖/矛盾/分歧
public enum ConflictNature: String, Sendable {
    case override
    case contradiction
    case divergence
}

/// 规则冲突描述 — 含冲突性质和解决方案
public struct RuleConflict: Sendable {
    public let description: String
    public let nature: ConflictNature
    public let resolution: String
    public init(description: String, nature: ConflictNature, resolution: String) {
        self.description = description
        self.nature = nature
        self.resolution = resolution
    }
}

/// 规则候选 — 经检索匹配的法规/判例/指南条目
public struct RuleCandidate: Sendable {
    public let wikilink: String
    public let title: String
    public let content: String
    public let source: RuleSource
    public let sourceLevel: Int
    public let effectiveDate: Date?
    public let conflicts: [RuleConflict]
    public let evidence: [EvidenceLink]
    public let score: Double
    public init(
        wikilink: String, title: String, content: String, source: RuleSource, sourceLevel: Int = 3,
        effectiveDate: Date? = nil, conflicts: [RuleConflict] = [], evidence: [EvidenceLink] = [], score: Double = 0
    ) {
        self.wikilink = wikilink
        self.title = title
        self.content = content
        self.source = source
        self.sourceLevel = sourceLevel
        self.effectiveDate = effectiveDate
        self.conflicts = conflicts
        self.evidence = evidence
        self.score = score
    }
}

/// 适用规则集合 — 包含候选规则、冲突和约束摘要
public struct ApplicableRules: Sendable {
    public let candidates: [RuleCandidate]
    public let conflicts: [RuleConflict]
    public let constraintSummary: String
    public init(candidates: [RuleCandidate] = [], conflicts: [RuleConflict] = [], constraintSummary: String = "") {
        self.candidates = candidates
        self.conflicts = conflicts
        self.constraintSummary = constraintSummary
    }
    public func injectableTokens(maxTokens: Int? = nil) -> String {
        let limit: Int = maxTokens ?? 3000
        var parts: [String] = []
        for candidate in candidates.prefix(5) {
            parts.append("## \(candidate.title)\n来源: \(candidate.wikilink)\n\(candidate.content)")
        }
        if !conflicts.isEmpty {
            parts.append("## 规则冲突")
            for conflict in conflicts {
                parts.append("- \(conflict.description): \(conflict.resolution)")
            }
        }
        if !constraintSummary.isEmpty { parts.append("## 实务约束\n\(constraintSummary)") }
        let full: String = parts.joined(separator: "\n\n---\n\n")
        let estimatedTokens: Int = full.count / 4
        return estimatedTokens > limit ? String(full.prefix(limit * 4)) : full
    }
}

/// 检索结果条目
public struct SearchResultItem: Sendable {
    public let title: String
    public let score: Double
    public let content: String
    public init(title: String, score: Double, content: String = "") {
        self.title = title
        self.score = score
        self.content = content
    }
}

/// 规则检索结果 — 包含所有候选规则
public struct RuleRetrievalResult: Sendable {
    public let candidates: [RuleCandidate]
    public init(candidates: [RuleCandidate] = []) {
        self.candidates = candidates
    }
}

/// 卡片变更类型 — 用于观察者通知
public enum CardChange: Sendable {
    case created(String)
    case modified(String)
    case deleted(String)
}
