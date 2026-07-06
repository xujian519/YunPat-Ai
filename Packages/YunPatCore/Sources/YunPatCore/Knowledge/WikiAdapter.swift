import Foundation
public actor WikiAdapter {
    public let vaultPath: URL
    public var embeddingProvider: EmbeddingProvider?
    public var semanticIndex: SemanticIndex?

    public init(vaultPath: URL, embeddingProvider: EmbeddingProvider? = nil, semanticIndex: SemanticIndex? = nil) {
        self.vaultPath = vaultPath
        self.embeddingProvider = embeddingProvider
        self.semanticIndex = semanticIndex
    }
    public func readSchema() async throws -> String {
        try String(contentsOf: vaultPath.appendingPathComponent("AGENTS.md"), encoding: .utf8)
    }
    public func readModuleIndex(_ module: WikiModule) async throws -> String {
        let url = vaultPath.appendingPathComponent("Wiki/\(module.rawValue)/index.md")
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }
    public func readPage(_ wikilink: String) async throws -> String {
        let cleaned = wikilink.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
        let url = vaultPath.appendingPathComponent("Wiki/\(cleaned).md")
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }
    nonisolated public func parseWikilinks(from indexContent: String) -> [String] {
        let pattern: String = #"\[\[([^\]]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(indexContent.startIndex..., in: indexContent)
        return regex.matches(in: indexContent, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: indexContent) else { return nil }
            return String(indexContent[range])
        }
    }
    public func readConceptIndex() async throws -> String {
        let url = vaultPath.appendingPathComponent("Wiki/Concept-Index.md")
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }
    public func readCard(_ id: String) async throws -> String {
        let url = vaultPath.appendingPathComponent("Wiki/Cards/\(id).md")
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }
    public func createCard(name: String, content: String) async throws {
        let cardsDir = vaultPath.appendingPathComponent("Wiki/Cards")
        try FileManager.default.createDirectory(at: cardsDir, withIntermediateDirectories: true)
        let cardContent: String = """
            ---
            name: \(name)
            ---
            \(content)
            """
        try cardContent.write(to: cardsDir.appendingPathComponent("\(name).md"), atomically: true, encoding: .utf8)
    }
    public func deprecateCard(name: String) async throws {
        let original = vaultPath.appendingPathComponent("Wiki/Cards/\(name).md")
        guard FileManager.default.fileExists(atPath: original.path) else { return }
        let deprecated = vaultPath.appendingPathComponent("Wiki/Cards/\(name).md.deprecated")
        try FileManager.default.moveItem(at: original, to: deprecated)
    }
    public func semanticSearch(query: String) throws -> [SearchResultItem] {
        try keywordFallbackSearch(query: query)
    }

    /// 异步语义搜索 — 优先使用 EmbeddingProvider + SemanticIndex，回退到关键词
    public func semanticSearchAsync(query: String, topK: Int = 10) async throws -> [SearchResultItem] {
        if let provider = embeddingProvider, let index = semanticIndex {
            let ready: Bool = await provider.isReady
            let available: Bool = await index.isAvailable
            if ready && available {
                let embeddings: [[Float]] = try await provider.embed([query])
                if let queryEmbedding: [Float] = embeddings.first {
                    let hits: [IndexHit] = try await index.search(
                        queryEmbedding: queryEmbedding, topK: topK, minScore: 0.3
                    )
                    return hits.map { hit in
                        SearchResultItem(title: hit.title, score: hit.score, content: hit.chunkText)
                    }
                }
            }
        }
        return try keywordFallbackSearch(query: query)
    }

    private func keywordFallbackSearch(query: String) -> [SearchResultItem] {
        let wikiDir = vaultPath.appendingPathComponent("Wiki")
        guard FileManager.default.fileExists(atPath: wikiDir.path) else { return [] }
        let files: [URL] = (try? FileManager.default.contentsOfDirectory(at: wikiDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" && !$0.lastPathComponent.lowercased().hasPrefix("index") }) ?? []
        var results: [SearchResultItem] = []
        let queryLower = query.lowercased()
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if content.lowercased().contains(queryLower) {
                let title: String = content.components(separatedBy: .newlines).first?
                    .replacingOccurrences(of: "^#\\s+", with: "", options: .regularExpression)
                    ?? file.deletingPathExtension().lastPathComponent
                let score = Double(content.lowercased().components(separatedBy: queryLower).count - 1)
                results.append(SearchResultItem(title: title, score: score, content: content))
            }
        }
        return results
    }
    public func retrieveRules(query: String, module: WikiModule? = nil) async throws -> RuleRetrievalResult {
        let modules: [WikiModule] = module.map { [$0] } ?? WikiModule.allCases
        var candidates: [RuleCandidate] = []
        for mod in modules {
            let index: String = try await readModuleIndex(mod)
            let links = parseWikilinks(from: index)
            for link in links {
                let content: String = try await readPage(link)
                let matches: Bool = link.lowercased().contains(query.lowercased())
                    || content.lowercased().contains(query.lowercased())
                guard matches, !content.isEmpty else { continue }
                let title: String = content.components(separatedBy: .newlines).first?
                    .replacingOccurrences(of: "^#\\s+", with: "", options: .regularExpression) ?? link
                candidates.append(RuleCandidate(
                    wikilink: link,
                    title: title,
                    content: content,
                    source: sourceForModule(mod),
                    sourceLevel: sourceLevelForModule(mod),
                    score: 0.5
                ))
            }
        }
        return RuleRetrievalResult(candidates: candidates)
    }
    private func sourceForModule(_ module: WikiModule) -> RuleSource {
        switch module {
        case .laws: return .statute("")
        case .examinationGuide: return .guideline("")
        case .patentJudgments, .reexamination: return .judgment("")
        case .patentInfringement: return .precedent("")
        default: return .doctrine
        }
    }
    private func sourceLevelForModule(_ module: WikiModule) -> Int {
        switch module {
        case .laws: return 1
        case .examinationGuide: return 2
        case .patentPractice: return 3
        case .patentInfringement: return 4
        case .patentJudgments: return 5
        case .reexamination: return 5
        case .books: return 6
        }
    }
    public func archiveQuery(query: String, result: String) async throws {
        let queriesDir: URL = vaultPath.appendingPathComponent("Queries")
        try FileManager.default.createDirectory(at: queriesDir, withIntermediateDirectories: true)
        let dateStr: String = ISO8601DateFormatter().string(from: Date())
        let filename: String = "query-\(dateStr).md"
        let content: String = """
            # \(query)
            \(result)
            """
        try content.write(to: queriesDir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }
    public func readCrossReferences() async throws -> [CrossReference] {
        let wikiDir: URL = vaultPath.appendingPathComponent("Wiki")
        var refs: [CrossReference] = []
        let files: [URL] = (try? FileManager.default.contentsOfDirectory(at: wikiDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }) ?? []
        for file in files {
            let content: String = try String(contentsOf: file, encoding: .utf8)
            refs += parseCrossReferences(in: content)
        }
        return refs
    }

    public func parseCrossReferences(in content: String) -> [CrossReference] {
        var refs: [CrossReference] = []
        let lines: [String] = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            if line.contains("⟷一致") {
                let concept = extractConcept(from: line)
                refs.append(
                    CrossReference(
                        concept: concept, line: index + 1,
                        nature: .consistent,
                        annotation: line.trimmingCharacters(in: .whitespaces)
                    ))
            } else if line.contains("⟷分歧") || line.contains("⟷标准分歧") {
                let concept = extractConcept(from: line)
                let desc =
                    line.components(separatedBy: "⟷分歧").last
                    ?? line.components(separatedBy: "⟷标准分歧").last
                refs.append(
                    CrossReference(
                        concept: concept, line: index + 1,
                        nature: .divergence,
                        annotation: desc?.trimmingCharacters(in: CharacterSet(charactersIn: " ()（）"))
                            .trimmingCharacters(in: .whitespaces) ?? line
                    ))
            }
        }
        return refs
    }
    private func extractConcept(from line: String) -> String {
        if let start = line.range(of: "[[")?.upperBound,
            let end = line[start...].range(of: "]]")?.lowerBound {
            return String(line[start..<end])
        }
        return line.components(separatedBy: .whitespaces).prefix(3).joined(separator: " ")
    }
}
// MARK: - Cross Reference Types
/// 跨源引用标注
public struct CrossReference: Sendable {
    public let concept: String
    public let line: Int
    public let nature: CrossReferenceNature
    public let annotation: String
    public init(concept: String, line: Int, nature: CrossReferenceNature, annotation: String) {
        self.concept = concept
        self.line = line
        self.nature = nature
        self.annotation = annotation
    }
}
public enum CrossReferenceNature: String, Sendable {
    case consistent
    case divergence
}
