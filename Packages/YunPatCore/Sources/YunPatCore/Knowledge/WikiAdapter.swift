import Foundation

public final class WikiAdapter: @unchecked Sendable {
    public let vaultPath: URL

    public init(vaultPath: URL) { self.vaultPath = vaultPath }

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

    public func parseWikilinks(from indexContent: String) -> [String] {
        let pattern = #"\[\[([^\]]+)\]\]"#
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

    /// 解析 Wiki 页面中的跨源标注：⟷一致 / ⟷分歧
    public func parseCrossReferences(in content: String) -> [CrossReference] {
        var refs: [CrossReference] = []
        let lines = content.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            if line.contains("⟷一致") {
                let concept = extractConcept(from: line)
                refs.append(CrossReference(
                    concept: concept, line: i + 1,
                    nature: .consistent,
                    annotation: line.trimmingCharacters(in: .whitespaces)
                ))
            } else if line.contains("⟷分歧") || line.contains("⟷标准分歧") {
                let concept = extractConcept(from: line)
                let desc = line.components(separatedBy: "⟷分歧").last
                    ?? line.components(separatedBy: "⟷标准分歧").last
                refs.append(CrossReference(
                    concept: concept, line: i + 1,
                    nature: .divergence,
                    annotation: desc?.trimmingCharacters(in: CharacterSet(charactersIn: " ()（）")).trimmingCharacters(in: .whitespaces) ?? line
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

/// 跨源引用标注
public struct CrossReference: Sendable {
    public let concept: String
    public let line: Int
    public let nature: CrossReferenceNature
    public let annotation: String

    public init(concept: String, line: Int, nature: CrossReferenceNature, annotation: String) {
        self.concept = concept; self.line = line; self.nature = nature; self.annotation = annotation
    }
}

public enum CrossReferenceNature: String, Sendable {
    case consistent   // ⟷一致 — 多源一致
    case divergence   // ⟷分歧 — 多源分歧
}
