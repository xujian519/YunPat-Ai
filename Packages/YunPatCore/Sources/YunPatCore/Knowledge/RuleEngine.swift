import Foundation

/// 规则检索引擎 — 六步检索管道：概念索引 → 语义兜底 → 模块广度 → 冲突解决
///
/// 输入：`StructuredFacts`（技术方案结构化事实）
/// 输出：`ApplicableRules`（适用于本案的法条/判例/指南规则）
public actor RuleEngine {
    private let adapter: WikiAdapter
    private let vectorSearch: VectorSearch
    public init(adapter: WikiAdapter, vectorSearch: VectorSearch = .shared) {
        self.adapter = adapter
        self.vectorSearch = vectorSearch
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
        if candidates.count < 3 && !allKeywords.isEmpty {
            let query: String = allKeywords.joined(separator: " ")
            // 优先使用 WikiAdapter 的语义搜索（走 EmbeddingProvider + SemanticIndex）
            let semanticResults: [SearchResultItem] =
                (try? await adapter.semanticSearchAsync(query: query, topK: 5)) ?? []
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
                        query: query, candidates: wikiTexts, topK: 5, minScore: 0.25)
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
                    for link in adapter.parseWikilinks(from: index).prefix(10) {
                        if let candidate: RuleCandidate = try? await readCandidate(wikilink: link) {
                            candidates.append(candidate)
                        }
                    }
                }
            }
        }

        let resolved: [RuleCandidate] = resolveConflicts(candidates)
        return ApplicableRules(
            candidates: resolved, constraintSummary: resolved.prefix(3).map(\.title).joined(separator: "、"))
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
