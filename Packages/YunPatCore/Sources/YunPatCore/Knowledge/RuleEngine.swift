import Foundation

public actor RuleEngine {
    private let adapter: WikiAdapter
    public init(adapter: WikiAdapter) { self.adapter = adapter }

    public func retrieveRules(for facts: StructuredFacts) async throws -> ApplicableRules {
        var candidates: [RuleCandidate] = []
        let conceptIndex = try await adapter.readConceptIndex()
        if !conceptIndex.isEmpty {
            for link in findMatchingLinks(in: conceptIndex, for: facts) {
                if let c = try? await readCandidate(wikilink: link) { candidates.append(c) }
            }
        }
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
}
