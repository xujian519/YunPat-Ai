import Foundation

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
        let conceptIndex = try await adapter.readConceptIndex()
        var matchedLinks = Set<String>()
        if !conceptIndex.isEmpty {
            let links = findMatchingLinks(in: conceptIndex, for: facts)
            matchedLinks.formUnion(links)
            for link in links {
                if let c = try? await readCandidate(wikilink: link) { candidates.append(c) }
            }
        }

        // Step 2: Semantic search fallback (missed concepts)
        let allKeywords = (facts.inventionPoints + [facts.technicalField, facts.problem])
            .filter { !$0.isEmpty }
        if candidates.count < 3 && !allKeywords.isEmpty {
            let query = allKeywords.joined(separator: " ")
            let wikiTexts = try await collectAllWikiSummaries()
            if !wikiTexts.isEmpty {
                let topIndices = await vectorSearch.search(query: query, candidates: wikiTexts, topK: 5, minScore: 0.25)
                for (idx, _) in topIndices {
                    let link = wikiTexts[idx]
                    if !matchedLinks.contains(link) {
                        if let c = try? await readCandidate(wikilink: link) {
                            candidates.append(c)
                            matchedLinks.insert(link)
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
                        if let c = try? await readCandidate(wikilink: link) { candidates.append(c) }
                    }
                }
            }
        }

        let resolved = resolveConflicts(candidates)
        return ApplicableRules(candidates: resolved, constraintSummary: resolved.prefix(3).map(\.title).joined(separator: "、"))
    }

    public func resolveConflicts(_ candidates: [RuleCandidate]) -> [RuleCandidate] {
        candidates.sorted { $0.sourceLevel == $1.sourceLevel ? $0.score > $1.score : $0.sourceLevel < $1.sourceLevel }
    }

    private func findMatchingLinks(in index: String, for facts: StructuredFacts) -> [String] {
        var links: [String] = []
        let keywords = facts.inventionPoints + [facts.technicalField, facts.problem]
        for line in index.components(separatedBy: .newlines) where line.hasPrefix("- [[") {
            for kw in keywords where !kw.isEmpty && line.localizedCaseInsensitiveContains(kw) {
                let pattern = #"\[\[([^\]]+)\]\]"#
                if let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let range = Range(match.range(at: 1), in: line) {
                    links.append(String(line[range]))
                }
            }
        }
        return links
    }

    private func readCandidate(wikilink: String) async throws -> RuleCandidate? {
        let content = try await adapter.readPage(wikilink)
        guard !content.isEmpty else { return nil }
        let title = content.components(separatedBy: .newlines).first?.replacingOccurrences(of: "# ", with: "") ?? wikilink
        return RuleCandidate(wikilink: wikilink, title: title, content: content, source: .doctrine, sourceLevel: 3, score: 0.5)
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
