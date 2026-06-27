import Foundation

public enum WikiModule: String, CaseIterable {
    case patentPractice = "专利实务"
    case examinationGuide = "审查指南"
    case patentInfringement = "专利侵权"
    case patentJudgments = "专利判决"
    case reexamination = "复审无效"
    case laws = "法律法规"
    case books = "书籍"
}

public struct StructuredFacts: Sendable {
    public let technicalField: String
    public let problem: String
    public let inventionPoints: [String]
    public let missingInfo: [String]
    public let sourceDocument: URL?
    public init(technicalField: String = "", problem: String = "", inventionPoints: [String] = [], missingInfo: [String] = [], sourceDocument: URL? = nil) {
        self.technicalField = technicalField; self.problem = problem; self.inventionPoints = inventionPoints; self.missingInfo = missingInfo; self.sourceDocument = sourceDocument
    }
}

public enum RuleSource: Sendable { case statute(String); case guideline(String); case precedent(String); case judgment(String); case doctrine }

public struct EvidenceLink: Sendable {
    public let source: RuleSource; public let wikilink: String; public let excerpt: String
    public init(source: RuleSource, wikilink: String, excerpt: String) { self.source = source; self.wikilink = wikilink; self.excerpt = excerpt }
}

public enum ConflictNature: String, Sendable { case override; case contradiction; case divergence }

public struct RuleConflict: Sendable {
    public let description: String; public let nature: ConflictNature; public let resolution: String
    public init(description: String, nature: ConflictNature, resolution: String) { self.description = description; self.nature = nature; self.resolution = resolution }
}

public struct RuleCandidate: Sendable {
    public let wikilink: String; public let title: String; public let content: String
    public let source: RuleSource; public let sourceLevel: Int; public let effectiveDate: Date?
    public let conflicts: [RuleConflict]; public let evidence: [EvidenceLink]; public let score: Double
    public init(wikilink: String, title: String, content: String, source: RuleSource, sourceLevel: Int = 3, effectiveDate: Date? = nil, conflicts: [RuleConflict] = [], evidence: [EvidenceLink] = [], score: Double = 0) {
        self.wikilink = wikilink; self.title = title; self.content = content; self.source = source; self.sourceLevel = sourceLevel; self.effectiveDate = effectiveDate; self.conflicts = conflicts; self.evidence = evidence; self.score = score
    }
}

public struct ApplicableRules: Sendable {
    public let candidates: [RuleCandidate]; public let conflicts: [RuleConflict]; public let constraintSummary: String
    public init(candidates: [RuleCandidate] = [], conflicts: [RuleConflict] = [], constraintSummary: String = "") { self.candidates = candidates; self.conflicts = conflicts; self.constraintSummary = constraintSummary }
    public func injectableTokens(maxTokens: Int? = nil) -> String {
        let limit = maxTokens ?? 3000; var parts: [String] = []
        for c in candidates.prefix(5) { parts.append("## \(c.title)\n来源: \(c.wikilink)\n\(c.content)") }
        if !conflicts.isEmpty { parts.append("## 规则冲突"); for c in conflicts { parts.append("- \(c.description): \(c.resolution)") } }
        if !constraintSummary.isEmpty { parts.append("## 实务约束\n\(constraintSummary)") }
        let full = parts.joined(separator: "\n\n---\n\n"); let estimatedTokens = full.count / 4
        return estimatedTokens > limit ? String(full.prefix(limit * 4)) : full
    }
}

public enum CardChange: Sendable { case created(String); case modified(String); case deleted(String) }
