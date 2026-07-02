import Foundation

// MARK: - AuthorityLevel

/// 来源权威等级
///
/// 法律知识检索中，不同来源的公信力决定结果的采信顺序。
/// 例如：法律条文 > 司法解释 > 学术论文。
public enum AuthorityLevel: String, Sendable, Comparable {
    /// 法律条文、审查指南等最高权威
    case primary
    /// 司法解释、典型案例、复审/无效决定
    case secondary
    /// 学术论文、行业文章
    case tertiary
    /// 未知来源
    case unknown

    public static func < (lhs: AuthorityLevel, rhs: AuthorityLevel) -> Bool {
        rank(lhs) < rank(rhs)
    }

    private static func rank(_ level: AuthorityLevel) -> Int {
        switch level {
        case .primary: return 0
        case .secondary: return 1
        case .tertiary: return 2
        case .unknown: return 3
        }
    }
}

// MARK: - AuthorityScore

/// 权威评分结果
public struct AuthorityScore: Sendable {
    /// 权威等级
    public let level: AuthorityLevel
    /// 权威分数（0-1）
    public let score: Double
    /// 来源标识
    public let source: String
    /// 分级依据说明
    public let reason: String

    public init(level: AuthorityLevel, score: Double, source: String, reason: String) {
        self.level = level
        self.score = score
        self.source = source
        self.reason = reason
    }
}

// MARK: - AuthorityScorer

/// 权威评分服务 — 对检索结果按其来源可信度加权
///
/// 移植自 XiaoNuo 知识库的权威排序规则。
/// 在 HybridRetriever 融合后调用 `reRank`，对排名结果进行权威加权重排。
public actor AuthorityScorer {
    public static let shared: AuthorityScorer = AuthorityScorer()
    private init() {}

    // MARK: - Classification

    /// 根据来源字符串判定权威等级
    ///
    /// 按关键词匹配：
    /// - 法律条文类：专利法、实施细则、审查指南
    /// - 司法解释类：司法解释、最高法院、典型案例、指导案例
    /// - 决定文书类：复审决定、无效宣告、无效决定、复审委、专利复审
    /// - 学术类：大学学报、学报、期刊、论文、doi、cnki
    /// - 行业类：博客、blog、技术文章、科普、知乎、newsletter
    /// - 其余归为 unknown
    public func classifyAuthority(source: String) -> AuthorityLevel {
        let lower = source.lowercased()

        // Primary: 立法 / 行政法规 / 审查指南
        let primaryKeywords: [String] = [
            "专利法", "专利法实施细则", "实施细则",
            "审查指南", "专利审查指南",
            "中华人民共和国专利法"
        ]
        for keyword in primaryKeywords where lower.contains(keyword) {
            return .primary
        }

        // Secondary: 司法解释 / 最高法判决 / 典型案例 / 复审无效决定
        let secondaryKeywords: [String] = [
            "司法解释", "最高人民法院", "最高法院",
            "典型案例", "指导案例", "公报案例",
            "复审决定", "无效宣告", "无效决定",
            "复审委", "专利复审", "合议组",
            "知识产权法院", "知识产权法庭"
        ]
        for keyword in secondaryKeywords where lower.contains(keyword) {
            return .secondary
        }

        // Tertiary: 学术 / 行业
        let tertiaryKeywords: [String] = [
            "大学学报", "学报", "期刊", "论文",
            "doi", "cnki", "万方", "知网",
            "博客", "blog", "技术文章",
            "科普", "知乎", "newsletter",
            "微信公众号", "知乎专栏"
        ]
        for keyword in tertiaryKeywords where lower.contains(keyword) {
            return .tertiary
        }

        return .unknown
    }

    // MARK: - Scoring

    /// 对来源和内容计算权威分数
    ///
    /// - 分数基数由关键词匹配决定
    /// - 内容字段可提级：若内容中出现法律条款引用，对 secondary/tertiary 加分
    /// - source 为 URL 时尝试提取域名特征辅助判断
    public func score(source: String, content: String) -> AuthorityScore {
        let level = classifyAuthority(source: source)
        let baseScore = baseScoreFor(level: level, source: source)

        // 内容增强：分析正文是否包含权威引用
        let enhancedScore = enhanceWithContent(baseScore: baseScore, level: level, content: content)

        return AuthorityScore(
            level: level,
            score: min(enhancedScore, 1.0),
            source: source,
            reason: reasonFor(level: level, enhanced: enhancedScore != baseScore)
        )
    }

    /// 按权威等级返回基础分数
    /// 按权威等级和来源子类返回基础分数
    ///
    /// tertiary 内部区分：学术类（0.60）vs 行业类（0.40），其余 0.50。
    private func baseScoreFor(level: AuthorityLevel, source: String) -> Double {
        switch level {
        case .primary: return 1.0
        case .secondary: return 0.80
        case .tertiary:
            let lower = source.lowercased()
            let isAcademic: Bool =
                lower.contains("大学学报") || lower.contains("学报")
                || lower.contains("期刊") || lower.contains("论文")
                || lower.contains("doi") || lower.contains("cnki")
                || lower.contains("万方") || lower.contains("知网")
            let isIndustry: Bool =
                lower.contains("博客") || lower.contains("blog")
                || lower.contains("技术文章") || lower.contains("科普")
                || lower.contains("知乎") || lower.contains("newsletter")
                || lower.contains("微信公众号")
            if isAcademic { return 0.60 }
            if isIndustry { return 0.40 }
            return 0.50
        case .unknown: return 0.30
        }
    }

    /// 根据正文内容增强权威分数
    ///
    /// 在同一等级内，正文引用法律条文或包含学术特征可提升分数。
    /// - secondary：含法律引用提升至 0.90
    /// - tertiary：含法律引用至少 0.65，含学术特征至少 0.55
    /// - unknown：含法律引用提升至 0.45，含学术特征提升至 0.35
    private func enhanceWithContent(baseScore: Double, level: AuthorityLevel, content: String) -> Double {
        guard !content.isEmpty else { return baseScore }

        let lowerContent = content.lowercased()

        // 检测正文中是否引用正式法律条文
        let hasLegalReference: Bool =
            lowerContent.contains("专利法第")
            || lowerContent.contains("实施细则第")
            || lowerContent.contains("审查指南第")
            || lowerContent.contains("最高人民法院")
            || lowerContent.contains("第") && lowerContent.contains("条")

        // 检测正文中是否有学术特征
        let hasAcademicFeature: Bool =
            lowerContent.contains("参考文献")
            || lowerContent.contains("摘要")
            || lowerContent.contains("关键词")
            || lowerContent.contains("abstract")

        switch level {
        case .primary:
            return baseScore

        case .secondary:
            if hasLegalReference { return 0.90 }
            return baseScore

        case .tertiary:
            if hasLegalReference { return max(baseScore, 0.65) }
            if hasAcademicFeature { return max(baseScore, 0.55) }
            return baseScore

        case .unknown:
            if hasLegalReference { return 0.45 }
            if hasAcademicFeature { return 0.35 }
            return baseScore
        }
    }

    /// 生成分级理由说明
    private func reasonFor(level: AuthorityLevel, enhanced: Bool) -> String {
        let base: String = {
            switch level {
            case .primary: return "法律条文/审查指南 — 最高权威"
            case .secondary: return "司法解释/典型案例/复审决定"
            case .tertiary: return "学术论文/行业文章"
            case .unknown: return "未知来源"
            }
        }()
        return enhanced ? "\(base)（正文含权威引用，加权提升）" : base
    }

    // MARK: - Re-Ranking

    /// 对融合检索结果进行权威加权重排
    ///
    /// 计算方法：`combinedScore = originalScore * authorityScore`，
    /// 然后按 combinedScore 降序重排并更新 rank 字段。
    /// - Parameter results: HybridRetriever 融合后的排名结果
    /// - Returns: 按权威加权后重新排名的结果
    public func reRank(results: [RankedResult]) async -> [RankedResult] {
        guard !results.isEmpty else { return [] }

        // 对每个结果按正文内容计算权威分数（RankedResult.source 为检索来源而非文档出处）
        let scored: [RankedResult] = results.map { (result: RankedResult) in
            let authority: AuthorityScore = score(source: result.content, content: result.content)
            let combinedScore: Double = result.score * authority.score
            return RankedResult(
                documentId: result.documentId,
                content: result.content,
                source: result.source,
                score: combinedScore,
                rank: 0
            )
        }

        // 降序排列并重新编号 rank
        let sorted = scored.sorted { $0.score > $1.score }
        return sorted.enumerated().map { (idx, result) in
            RankedResult(
                documentId: result.documentId,
                content: result.content,
                source: result.source,
                score: result.score,
                rank: idx + 1
            )
        }
    }
}
