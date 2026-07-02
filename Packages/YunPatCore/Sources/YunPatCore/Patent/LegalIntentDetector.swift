import Foundation

// MARK: - Enums

public enum CaseType: String, Sendable, Codable {
    case noveltySearch
    case patentability
    case drafting
    case oaResponse
    case rejectionResponse
    case reexamination
    case invalidation
    case infringement
    case fto
    case validity
    case legalStatus
    case generalLegal
}

public enum RunMode: String, Sendable {
    case direct
    case legalbusJudgment
    case flexiblePlan
    case hybrid
}

// MARK: - Result

public struct LegalIntentResult: Sendable {
    public let isLegalIntent: Bool
    public let suggestedMode: RunMode
    public let caseType: CaseType?
    public let confidence: Double
    public let matchedKeywords: [String]
    public let suggestion: String
    public let explicitTrigger: Bool

    public init(
        isLegalIntent: Bool,
        suggestedMode: RunMode,
        caseType: CaseType?,
        confidence: Double,
        matchedKeywords: [String],
        suggestion: String,
        explicitTrigger: Bool
    ) {
        self.isLegalIntent = isLegalIntent
        self.suggestedMode = suggestedMode
        self.caseType = caseType
        self.confidence = confidence
        self.matchedKeywords = matchedKeywords
        self.suggestion = suggestion
        self.explicitTrigger = explicitTrigger
    }
}

// MARK: - Detector Actor

public actor LegalIntentDetector {

    private struct KeywordEntry: Sendable {
        let keywords: [String]
        let caseType: CaseType
        let runMode: RunMode
        let requiresPatentContext: Bool
    }

    private let keywordTable: [KeywordEntry] = [
        KeywordEntry(
            keywords: ["无效", "宣告", "无效宣告", "无效请求"],
            caseType: .invalidation,
            runMode: .flexiblePlan,
            requiresPatentContext: false
        ),
        KeywordEntry(
            keywords: ["侵权", "侵权分析", "侵权判断", "全面覆盖"],
            caseType: .infringement,
            runMode: .flexiblePlan,
            requiresPatentContext: false
        ),
        KeywordEntry(
            keywords: ["新颖性", "新颖性判断"],
            caseType: .noveltySearch,
            runMode: .legalbusJudgment,
            requiresPatentContext: false
        ),
        KeywordEntry(
            keywords: ["创造性", "创造性判断", "三步法"],
            caseType: .patentability,
            runMode: .legalbusJudgment,
            requiresPatentContext: false
        ),
        KeywordEntry(
            keywords: ["撰写", "专利申请", "写专利", "专利撰写"],
            caseType: .drafting,
            runMode: .flexiblePlan,
            requiresPatentContext: false
        ),
        KeywordEntry(
            keywords: ["OA", "审查意见", "答复", "OA答复", "审查意见通知书"],
            caseType: .oaResponse,
            runMode: .flexiblePlan,
            requiresPatentContext: false
        ),
        KeywordEntry(
            keywords: ["驳回", "复审", "驳回复审"],
            caseType: .reexamination,
            runMode: .flexiblePlan,
            requiresPatentContext: false
        ),
        KeywordEntry(
            keywords: ["FTO", "自由实施", "自由实施分析"],
            caseType: .fto,
            runMode: .flexiblePlan,
            requiresPatentContext: false
        ),
        KeywordEntry(
            keywords: ["充分公开", "公开不充分"],
            caseType: .invalidation,
            runMode: .legalbusJudgment,
            requiresPatentContext: false
        ),
        KeywordEntry(
            keywords: ["清楚", "不清楚", "不支持"],
            caseType: .invalidation,
            runMode: .legalbusJudgment,
            requiresPatentContext: true
        )
    ]

    public init() {}

    public func detect(query: String) -> LegalIntentResult {
        let trimmed: String = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitTrigger: Bool = trimmed.hasPrefix("@legal")

        // Normalize: strip @legal prefix for keyword matching
        let searchText: String
        if explicitTrigger {
            searchText = String(trimmed.dropFirst("@legal".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            searchText = trimmed
        }

        // Collect all keyword matches with scores
        struct MatchCandidate: Sendable {
            let entry: KeywordEntry
            let matchedKeywords: [String]
            let score: Double
        }
        var matches: [MatchCandidate] = []

        for entry in keywordTable {
            let matched = entry.keywords.filter { keyword in
                searchText.localizedCaseInsensitiveContains(keyword)
            }
            guard !matched.isEmpty else { continue }

            // Score: fraction of keywords matched × entry weight, boosted for longer matches
            let coverageRatio: Double = Double(matched.count) / Double(entry.keywords.count)
            let keywordSpecificity = matched.map { Double($0.count) / 10.0 }.reduce(0, +) / Double(matched.count)
            let contextScore = entry.requiresPatentContext ? 0.7 : 1.0
            let score = coverageRatio * keywordSpecificity * contextScore

            matches.append(MatchCandidate(entry: entry, matchedKeywords: matched, score: score))
        }

        // Explicit @legal trigger boosts confidence floor
        let explicitBoost = explicitTrigger ? 0.15 : 0.0

        if let best = matches.max(by: { $0.score < $1.score }) {
            let baseConfidence: Double = min(best.score * 0.7 + 0.3 + explicitBoost, 1.0)
            let suggestion: String = makeSuggestion(
                caseType: best.entry.caseType,
                runMode: best.entry.runMode,
                matchedKeywords: best.matchedKeywords
            )
            return LegalIntentResult(
                isLegalIntent: true,
                suggestedMode: best.entry.runMode,
                caseType: best.entry.caseType,
                confidence: baseConfidence,
                matchedKeywords: best.matchedKeywords,
                suggestion: suggestion,
                explicitTrigger: explicitTrigger
            )
        }

        // No keyword match
        let mode: RunMode = explicitTrigger ? .flexiblePlan : .direct
        return LegalIntentResult(
            isLegalIntent: explicitTrigger,
            suggestedMode: mode,
            caseType: nil,
            confidence: explicitTrigger ? 0.3 : 0.0,
            matchedKeywords: [],
            suggestion: explicitTrigger
                ? "未识别到具体法律意图，建议进一步明确问题类型"
                : "",
            explicitTrigger: explicitTrigger
        )
    }

    private func makeSuggestion(caseType: CaseType, runMode: RunMode, matchedKeywords: [String]) -> String {
        let keywordsStr = matchedKeywords.joined(separator: "、")
        switch caseType {
        case .noveltySearch:
            return "检测到新颖性判断意图（关键词：\(keywordsStr)），建议使用 LegalBus 三步法进行分析"
        case .patentability:
            return "检测到创造性判断意图（关键词：\(keywordsStr)），建议使用 LegalBus 三步法进行分析"
        case .drafting:
            return "检测到专利撰写意图（关键词：\(keywordsStr)），建议启动灵活规划模式"
        case .oaResponse:
            return "检测到审查意见答复意图（关键词：\(keywordsStr)），建议启动灵活规划模式"
        case .rejectionResponse:
            return "检测到驳回决定答复意图（关键词：\(keywordsStr)），建议启动灵活规划模式"
        case .reexamination:
            return "检测到复审意图（关键词：\(keywordsStr)），建议启动灵活规划模式"
        case .invalidation:
            return "检测到无效宣告意图（关键词：\(keywordsStr)），建议使用 LegalBus 判断模式"
        case .infringement:
            return "检测到侵权分析意图（关键词：\(keywordsStr)），建议启动灵活规划模式"
        case .fto:
            return "检测到 FTO 分析意图（关键词：\(keywordsStr)），建议启动灵活规划模式"
        case .validity:
            return "检测到有效性分析意图（关键词：\(keywordsStr)）"
        case .legalStatus:
            return "检测到法律状态查询意图（关键词：\(keywordsStr)）"
        case .generalLegal:
            return "检测到通用法律意图（关键词：\(keywordsStr)）"
        }
    }
}
