import Foundation

/// 用户查询意图分类 — lawLookup / conceptExplain / caseAnalysis / comparison / ruleExplore / general
public enum QueryIntent: String, Sendable, CaseIterable {
    /// 法条查找：查询具体专利法条文
    case lawLookup
    /// 概念解释：理解法律术语或概念定义
    case conceptExplain
    /// 案例分析：分析具体案例或判决
    case caseAnalysis
    /// 对比分析：比较两个或以上的概念/法条/案例
    case comparison
    /// 规则探索：广泛检索相关规则、审查指南
    case ruleExplore
    /// 通用查询
    case general
}

/// 检索策略 — 定义混合检索中各维度的权重和深度
public struct RetrievalStrategy: Sendable {
    public let ftsWeight: Double
    public let vectorWeight: Double
    public let graphDepth: Int
    public let graphExpansion: Double
    public let limit: Int

    public init(
        ftsWeight: Double,
        vectorWeight: Double,
        graphDepth: Int = 1,
        graphExpansion: Double = 0.3,
        limit: Int = 10
    ) {
        self.ftsWeight = ftsWeight
        self.vectorWeight = vectorWeight
        self.graphDepth = graphDepth
        self.graphExpansion = graphExpansion
        self.limit = limit
    }
}

/// 查询路由器 — 分类用户意图并选择最优检索策略
public actor QueryRouter {

    public init() {}

    // MARK: - Intent Classification

    /// 基于正则关键词匹配分类用户意图
    /// - Parameter query: 用户查询文本
    /// - Returns: 分类后的查询意图
    public func classifyIntent(query: String) -> QueryIntent {
        // 1. 法条查找 — 匹配具体条文引用
        if matchesArticleCitation(query) { return .lawLookup }

        // 2. 对比分析 — 匹配对比模式
        if matchesComparisonPattern(query) { return .comparison }

        // 3. 案例分析 — 匹配案例/判决模式
        if matchesCasePattern(query) { return .caseAnalysis }

        // 4. 概念解释 — 匹配定义/解释模式
        if matchesConceptPattern(query) { return .conceptExplain }

        // 5. 规则探索 — 匹配广泛检索模式
        if matchesExplorationPattern(query) { return .ruleExplore }

        // 6. 默认通用查询
        return .general
    }

    // MARK: - Strategy Routing

    /// 根据意图选择检索策略
    /// - Parameter query: 用户查询文本
    /// - Returns: 对应的检索策略
    public func route(query: String) -> RetrievalStrategy {
        switch classifyIntent(query: query) {
        case .lawLookup:
            RetrievalStrategy(
                ftsWeight: 0.7, vectorWeight: 0.3,
                graphDepth: 2, limit: 5
            )
        case .conceptExplain:
            RetrievalStrategy(
                ftsWeight: 0.3, vectorWeight: 0.5,
                graphDepth: 2, limit: 3
            )
        case .caseAnalysis:
            RetrievalStrategy(
                ftsWeight: 0.4, vectorWeight: 0.3,
                graphDepth: 3, limit: 10
            )
        case .comparison:
            RetrievalStrategy(
                ftsWeight: 0.5, vectorWeight: 0.3,
                graphDepth: 2, limit: 5
            )
        case .ruleExplore:
            RetrievalStrategy(
                ftsWeight: 0.4, vectorWeight: 0.3,
                graphDepth: 4, limit: 20
            )
        case .general:
            RetrievalStrategy(
                ftsWeight: 0.5, vectorWeight: 0.5,
                graphDepth: 1, limit: 10
            )
        }
    }

    // MARK: - Pattern Matchers

    /// 法条引用：第X条、Art. X、§X、细则第X条、第X款
    private func matchesArticleCitation(_ query: String) -> Bool {
        let patterns: [Regex<Substring>] = [
            /第[一二三四五六七八九十百千\d]+条/,
            /Art(?:icle)?\.?\s*\d+/,
            /§\s*\d+/,
            /细则第[一二三四五六七八九十百千\d]+条/,
            /第[一二三四五六七八九十百千\d]+款/,
            /Rule\s+\d+/,
            /专利法第[一二三四五六七八九十百千\d]+条/
        ]
        return patterns.contains { query.contains($0) }
    }

    /// 对比模式：vs、与...区别、对比、比较、差异
    private func matchesComparisonPattern(_ query: String) -> Bool {
        let patterns: [Regex<Substring>] = [
            /\bvs\.?\b/,
            /与.+的区别/,
            /与.+区别/,
            /对比/,
            /比较/,
            /差异/,
            /不同于/,
            /相较/,
            /\bdiff(?:erence)?\b/,
            /compared?\s+(?:with|to)/
        ]
        return patterns.contains { query.contains($0) }
    }

    /// 案例模式：案例、判决、裁定、判例
    private func matchesCasePattern(_ query: String) -> Bool {
        let patterns: [Regex<Substring>] = [
            /案例/,
            /判决/,
            /裁定/,
            /判例/,
            /最高法/,
            /最高院/,
            /法院/,
            /诉讼/,
            /侵权.*案/,
            /\bcase\b/,
            /\bjudgment\b/,
            /\bprecedent\b/
        ]
        return patterns.contains { query.contains($0) }
    }

    /// 概念解释：什么是、定义、含义、概念、如何理解
    private func matchesConceptPattern(_ query: String) -> Bool {
        let patterns: [Regex<Substring>] = [
            /什么是/,
            /定义/,
            /含义/,
            /概念/,
            /如何理解/,
            /怎么理解/,
            /是什么意思/,
            /指什么/,
            /什么叫/,
            /\bwhat\s+is\b/,
            /\bdefine\b/,
            /\bdefinition\b/
        ]
        return patterns.contains { query.contains($0) }
    }

    /// 规则探索：检索、查找、搜索、相关、有哪些、规定
    private func matchesExplorationPattern(_ query: String) -> Bool {
        let patterns: [Regex<Substring>] = [
            /检索/,
            /查找/,
            /搜索/,
            /相关/,
            /有哪些/,
            /哪些.*规定/,
            /规定.*哪些/,
            /审查指南/,
            /指南.*规定/,
            /如何.*申请/,
            /程序/,
            /流程/,
            /要求/,
            /条件/,
            /期限/,
            /\bsearch\b/,
            /\bfind\b/,
            /\brelated\b/,
            /\bprocedure\b/
        ]
        return patterns.contains { query.contains($0) }
    }
}
