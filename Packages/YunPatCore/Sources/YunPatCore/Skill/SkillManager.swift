import Foundation

public actor SkillManager {
    private var skills: [SkillContent] = []

    public init() {}

    public func register(_ skill: SkillContent) {
        skills.append(skill)
    }

    /// 三级 RAG 匹配：触发词精确匹配 → 语义匹配(embedding) → 标签匹配
    public func match(for request: UserRequest, vectorSearch: VectorSearch? = nil) async -> [SkillMatch] {
        let content = request.content.lowercased()
        var results: [SkillMatch] = []

        for skill in skills {
            var score: Double = 0

            // 1. 触发词精确匹配 → 权重 10（已在关键字匹配中覆盖）
            for t in skill.manifest.triggers {
                if content.contains(t.lowercased()) {
                    score += 10
                    break
                }
            }

            // 2. 语义匹配 (embedding cos-sim) → 权重 0-5
            if let vs = vectorSearch, let handler = await vs.embedHandler {
                let skillDesc = skill.manifest.description + " " + skill.manifest.tags.joined(separator: " ")
                if !skillDesc.trimmingCharacters(in: .whitespaces).isEmpty {
                    let texts = [request.content, skillDesc]
                    if let vectors = await handler(texts), vectors.count == 2 {
                        let sim = VectorSearch.cosineSimilarity(vectors[0], vectors[1])
                        score += Double(sim) * 5
                    }
                }
            }

            // 3. 标签匹配 → 权重 2
            for t in skill.manifest.tags {
                if content.contains(t.lowercased()) {
                    score += 2
                }
            }

            if score > 0 {
                results.append(SkillMatch(skill: skill, score: score))
            }
        }

        return results.sorted { $0.score > $1.score }
    }

    /// 向后兼容的纯关键字匹配
    public func matchByKeywords(for request: UserRequest) -> [SkillMatch] {
        let content = request.content.lowercased()
        return skills.compactMap { skill in
            var score: Double = 0
            for t in skill.manifest.triggers {
                if content.contains(t.lowercased()) { score += 10; break }
            }
            for t in skill.manifest.tags {
                if content.contains(t.lowercased()) { score += 2 }
            }
            return score > 0 ? SkillMatch(skill: skill, score: score) : nil
        }.sorted { $0.score > $1.score }
    }

    public func allSkills() -> [SkillContent] {
        skills
    }
}
