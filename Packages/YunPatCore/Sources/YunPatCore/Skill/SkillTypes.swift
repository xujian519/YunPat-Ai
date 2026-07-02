import Foundation

/// 技能清单 — 名称、版本、描述、作者、标签和触发词
public struct SkillManifest: Sendable, Codable {
    public let name: String
    public let displayName: String
    public let version: String
    public let description: String
    public let author: String
    public let tags: [String]
    public let triggers: [String]

    public init(
        name: String, displayName: String, version: String = "1.0.0", description: String = "", author: String = "",
        tags: [String] = [], triggers: [String] = []
    ) {
        self.name = name
        self.displayName = displayName
        self.version = version
        self.description = description
        self.author = author
        self.tags = tags
        self.triggers = triggers
    }
}

/// 技能内容 — 清单 + Markdown 正文
public struct SkillContent: Sendable {
    public let manifest: SkillManifest
    public let body: String

    public init(manifest: SkillManifest, body: String) {
        self.manifest = manifest
        self.body = body
    }
}

/// 技能匹配结果 — 匹配的技能内容和相似度评分
public struct SkillMatch: Sendable {
    public let skill: SkillContent
    public let score: Double
    public let manifest: SkillManifest

    public init(skill: SkillContent, score: Double) {
        self.skill = skill
        self.score = score
        self.manifest = skill.manifest
    }
}
