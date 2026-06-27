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
}
