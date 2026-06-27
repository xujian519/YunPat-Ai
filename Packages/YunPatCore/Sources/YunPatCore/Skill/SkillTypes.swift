import Foundation

public struct SkillManifest: Sendable, Codable {
    public let name: String
    public let displayName: String
    public let version: String
    public let description: String
    public let author: String
    public let tags: [String]
    public let triggers: [String]

    public init(name: String, displayName: String, version: String = "1.0.0", description: String = "", author: String = "", tags: [String] = [], triggers: [String] = []) {
        self.name = name
        self.displayName = displayName
        self.version = version
        self.description = description
        self.author = author
        self.tags = tags
        self.triggers = triggers
    }
}

public struct SkillContent: Sendable {
    public let manifest: SkillManifest
    public let body: String

    public init(manifest: SkillManifest, body: String) {
        self.manifest = manifest
        self.body = body
    }
}

public struct SkillMatch: Sendable {
    public let skill: SkillContent
    public let score: Double

    public init(skill: SkillContent, score: Double) {
        self.skill = skill
        self.score = score
    }
}
