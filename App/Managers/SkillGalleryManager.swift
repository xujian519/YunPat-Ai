import Foundation
import SwiftUI
import YunPatCore

@MainActor
final class SkillGalleryManager: ObservableObject {
    @Published var skills: [SkillMatch] = []
    @Published var selectedSkill: SkillMatch?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let skillManager: SkillManager

    init(skillManager: SkillManager = .shared) {
        self.skillManager = skillManager
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        var matches: [SkillMatch] = await skillManager.allSkills()

        if matches.isEmpty {
            let skillDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".agents/skills")
            if FileManager.default.fileExists(atPath: skillDir.path) {
                do {
                    _ = try await skillManager.scan(from: skillDir)
                    matches = await skillManager.allSkills()
                } catch {
                    errorMessage = "扫描技能目录失败: \(error.localizedDescription)"
                }
            }
        }

        skills = matches.sorted { $0.manifest.displayName < $1.manifest.displayName }

        if selectedSkill == nil {
            selectedSkill = skills.first
        }
        isLoading = false
    }

    func select(_ skill: SkillMatch) {
        selectedSkill = skill
    }

    func refresh() async {
        selectedSkill = nil
        await skillManager.removeAll()
        skills = []
        await load()
    }

    /// 在 ~/.agents/skills 下创建一个新的技能文件并注册到 SkillManager。
    func createSkill(_ request: SkillCreateRequest) async throws {
        let skillDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/skills")

        if !FileManager.default.fileExists(atPath: skillDir.path) {
            try FileManager.default.createDirectory(
                at: skillDir,
                withIntermediateDirectories: true
            )
        }

        let safeName = request.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        guard !safeName.isEmpty else {
            throw SkillCreateError.invalidName
        }

        let fileURL = skillDir.appendingPathComponent("\(safeName).skill.md")
        let manifest = SkillManifest(
            name: safeName,
            displayName: request.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            version: "1.0.0",
            description: request.description.trimmingCharacters(in: .whitespacesAndNewlines),
            author: "",
            tags: request.tags,
            triggers: request.triggers
        )
        let content = skillMarkdown(manifest: manifest, body: request.body)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let skillContent = SkillContent(manifest: manifest, body: request.body)
        await skillManager.register(skillContent)
    }

    private func skillMarkdown(manifest: SkillManifest, body: String) -> String {
        """
        ---
        name: \(manifest.name)
        displayName: \(manifest.displayName)
        version: \(manifest.version)
        description: \(manifest.description)
        author: \(manifest.author)
        tags: [\(manifest.tags.joined(separator: ", "))]
        triggers: [\(manifest.triggers.joined(separator: ", "))]
        ---
        \(body)
        """
    }
}

public struct SkillCreateRequest: Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let tags: [String]
    public let triggers: [String]
    public let body: String

    public init(
        name: String,
        displayName: String,
        description: String,
        tags: [String],
        triggers: [String],
        body: String
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.tags = tags
        self.triggers = triggers
        self.body = body
    }
}

public enum SkillCreateError: Error, Sendable {
    case invalidName
}
