import Foundation

/// 规则检索引擎 — 六步检索管道：概念索引 → 语义兜底 → 模块广度 → 冲突解决
///
/// 输入：`StructuredFacts`（技术方案结构化事实）
/// 输出：`ApplicableRules`（适用于本案的法条/判例/指南规则）
public actor RuleEngine {
    private let adapter: WikiAdapter
    private let vectorSearch: VectorSearch
    private let queryRouter: QueryRouter
    private let authorityScorer: AuthorityScorer
    public init(adapter: WikiAdapter, vectorSearch: VectorSearch = .shared,
                queryRouter: QueryRouter = QueryRouter(), authorityScorer: AuthorityScorer = .shared) {
        self.adapter = adapter
        self.vectorSearch = vectorSearch
        self.queryRouter = queryRouter
        self.authorityScorer = authorityScorer
    }

    /// 六步检索管道：概念提取 → 索引查询 → 语义兜底 → 全文读取 → 跨源解析 → 组装
    public func retrieveRules(for facts: StructuredFacts) async throws -> ApplicableRules {
        var candidates: [RuleCandidate] = []

        // Step 1: Concept Index lookup (exact match, 0 latency)
        let conceptIndex: String = try await adapter.readConceptIndex()
        var matchedLinks: Set<String> = Set<String>()
        if !conceptIndex.isEmpty {
            let links = findMatchingLinks(in: conceptIndex, for: facts)
            matchedLinks.formUnion(links)
            for link in links {
                if let candidate: RuleCandidate = try? await readCandidate(wikilink: link) {
                    candidates.append(candidate)
                }
            }
        }

        // Step 2: Semantic search fallback (missed concepts)
        let allKeywords = (facts.inventionPoints + [facts.technicalField, facts.problem])
            .filter { !$0.isEmpty }
        let query: String = allKeywords.joined(separator: " ")
        let strategy: RetrievalStrategy = await queryRouter.route(query: query)
        if candidates.count < 3 && !allKeywords.isEmpty {
            // 优先使用 WikiAdapter 的语义搜索（走 EmbeddingProvider + SemanticIndex）
            let semanticResults: [SearchResultItem] =
                (try? await adapter.semanticSearchAsync(query: query, topK: min(5, strategy.limit))) ?? []
            if !semanticResults.isEmpty {
                for hit in semanticResults {
                    let link: String = hit.title
                    if !matchedLinks.contains(link) {
                        if let candidate: RuleCandidate = try? await readCandidate(wikilink: link) {
                            candidates.append(candidate)
                            matchedLinks.insert(link)
                        }
                    }
                }
            } else {
                // 回退到 VectorSearch.shared（可能已配置 embedHandler）
                let wikiTexts: [String] = try await collectAllWikiSummaries()
                if !wikiTexts.isEmpty {
                    let topIndices: [(Int, Float)] = await vectorSearch.search(
                        query: query, candidates: wikiTexts, topK: min(5, strategy.limit), minScore: 0.25)
                    for (idx, _) in topIndices {
                        let link: String = wikiTexts[idx]
                        if !matchedLinks.contains(link) {
                            if let candidate: RuleCandidate = try? await readCandidate(wikilink: link) {
                                candidates.append(candidate)
                                matchedLinks.insert(link)
                            }
                        }
                    }
                }
            }
        }

        // Step 3: Module index breadth fallback (when both concept and semantic miss)
        if candidates.isEmpty {
            for module in [WikiModule.patentPractice, .examinationGuide, .laws] {
                if let index = try? await adapter.readModuleIndex(module) {
                    for link in adapter.parseWikilinks(from: index).prefix(strategy.limit) {
                        if let candidate: RuleCandidate = try? await readCandidate(wikilink: link) {
                            candidates.append(candidate)
                        }
                    }
                }
            }
        }

        let ranked: [RuleCandidate] = await reRankByAuthority(candidates, query: query)
        return ApplicableRules(
            candidates: ranked, constraintSummary: ranked.prefix(3).map(\.title).joined(separator: "、"))
    }

    /// 解决规则冲突 — 按 sourceLevel 升序（效力高优先）、同级按 score 降序
    public func resolveConflicts(_ candidates: [RuleCandidate]) -> [RuleCandidate] {
        candidates.sorted { $0.sourceLevel == $1.sourceLevel ? $0.score > $1.score : $0.sourceLevel < $1.sourceLevel }
    }

    private func findMatchingLinks(in index: String, for facts: StructuredFacts) -> [String] {
        var links: [String] = []
        let keywords: [String] = (facts.inventionPoints + [facts.technicalField, facts.problem])
            .filter { !$0.isEmpty }
        for line in index.components(separatedBy: .newlines) where line.hasPrefix("- [[") {
            let pattern: String = #"\[\[([^\]]+)\]\]"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                let range = Range(match.range(at: 1), in: line)
            else { continue }
            let linkName: String = String(line[range])

            // Extract tag keywords after ]]
            let afterBracketStart: Int = match.range.location + match.range.length
            let afterBracket: String = afterBracketStart < line.count
                ? String(line[line.index(line.startIndex, offsetBy: afterBracketStart)...]) : ""
            let tagWords: [String] = afterBracket.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }

            // Bidirectional match: user keyword contains concept term, or concept term contains user keyword
            let conceptTerms: [String] = [linkName] + tagWords
            let matched: Bool = keywords.contains { keyword in
                conceptTerms.contains { term in
                    keyword.localizedCaseInsensitiveContains(term) || term.localizedCaseInsensitiveContains(keyword)
                }
            }
            if matched { links.append(linkName) }
        }
        return links
    }

    private func readCandidate(wikilink: String) async throws -> RuleCandidate? {
        let content: String = try await adapter.readPage(wikilink)
        guard !content.isEmpty else { return nil }
        let title: String =
            content.components(separatedBy: .newlines).first?.replacingOccurrences(of: "# ", with: "") ?? wikilink
        return RuleCandidate(
            wikilink: wikilink, title: title, content: content, source: .doctrine, sourceLevel: 3, score: 0.5)
    }

    /// 收集所有 wiki 页面标题作为语义搜索候选集
    private func reRankByAuthority(_ candidates: [RuleCandidate], query: String) async -> [RuleCandidate] {
        guard !candidates.isEmpty else { return [] }
        let ranked: [RankedResult] = candidates.enumerated().map { (i, c) in
            RankedResult(documentId: c.wikilink, content: c.content, source: .hybrid, score: c.score, rank: i + 1)
        }
        let reRanked: [RankedResult] = await authorityScorer.reRank(results: ranked)
        let order: [String: Int] = Dictionary(
            uniqueKeysWithValues: reRanked.enumerated().map { ($0.element.documentId, $0.offset) })
        return candidates.sorted { (order[$0.wikilink] ?? 0) < (order[$1.wikilink] ?? 0) }
    }

    private func collectAllWikiSummaries() async throws -> [String] {
        var links: [String] = []
        for module in [WikiModule.patentPractice, .examinationGuide, .laws] {
            if let index = try? await adapter.readModuleIndex(module) {
                links.append(contentsOf: adapter.parseWikilinks(from: index))
            }
        }
        return Array(Set(links))
    }
}
