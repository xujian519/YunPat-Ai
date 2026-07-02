import Foundation

public final class SkillParser {
    public func parse(_ markdown: String) -> SkillContent? {
        let parts = markdown.components(separatedBy: "---\n")
        guard parts.count >= 3 else { return nil }
        let yamlBlock: String = parts[1]
        let body = parts[2...].joined(separator: "---\n")

        var dict: [String: String] = [:]
        for line in yamlBlock.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            dict[key] = value
        }

        let manifest = SkillManifest(
            name: dict["name"] ?? "unknown",
            displayName: dict["displayName"] ?? dict["name"] ?? "Unknown",
            version: dict["version"] ?? "1.0.0",
            description: dict["description"] ?? "",
            author: dict["author"] ?? "",
            tags: parseList(dict["tags"]),
            triggers: parseList(dict["triggers"])
        )
        return SkillContent(manifest: manifest, body: body)
    }

    private func parseList(_ raw: String?) -> [String] {
        (raw ?? "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
