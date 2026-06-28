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

    // MARK: - File Scanning

    /// 扫描磁盘上的 skill 目录，加载所有 .skill.md 文件
    public func scan(from directory: URL) async throws -> [SkillManifest] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }

        var manifests: [SkillManifest] = []
        let parser = SkillParser()

        // 收集所有 .skill.md 文件
        let files = (try? fm.subpathsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasSuffix(".skill.md") {
            let url = directory.appendingPathComponent(file)
            guard let content = try? String(contentsOf: url, encoding: .utf8),
                  let parsed = parser.parse(content) else { continue }
            skills.append(parsed)
            manifests.append(parsed.manifest)
        }
        return manifests
    }

    /// 加载内置 skill（从 App Bundle Resources/Skills/ 读取）
    public func loadBuiltinSkills() async throws -> [SkillManifest] {
        guard let builtinURL = Bundle.main.url(forResource: "Skills", withExtension: nil) else { return [] }
        return try await scan(from: builtinURL)
    }
}
