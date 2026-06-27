import Foundation

public actor SkillManager {
    private var skills: [SkillContent] = []

    public init() {}

    public func register(_ skill: SkillContent) {
        skills.append(skill)
    }

    public func match(for request: UserRequest) -> [SkillMatch] {
        let content = request.content.lowercased()
        return skills.compactMap { skill in
            var score: Double = 0
            for t in skill.manifest.triggers {
                if content.contains(t.lowercased()) {
                    score += 10
                    break
                }
            }
            for t in skill.manifest.tags {
                if content.contains(t.lowercased()) {
                    score += 2
                }
            }
            return score > 0 ? SkillMatch(skill: skill, score: score) : nil
        }.sorted { $0.score > $1.score }
    }

    public func allSkills() -> [SkillContent] {
        skills
    }
}
