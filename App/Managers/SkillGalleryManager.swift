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
}
