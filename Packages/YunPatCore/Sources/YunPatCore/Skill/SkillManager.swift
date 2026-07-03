import Foundation

/// 技能管理器 — 注册、匹配和生命周期管理
public actor SkillManager {
    private var skills: [SkillContent] = []

    public init() {}

    private static let _shared = SkillManager()
    public static var shared: SkillManager { _shared }

    public func register(_ skill: SkillContent) {
        skills.append(skill)
    }

    /// 三级 RAG 匹配：触发词精确匹配 → 语义匹配(embedding) → 标签匹配
    public func match(for request: UserRequest, vectorSearch: VectorSearch? = nil) async -> [SkillMatch] {
        let content: String = request.content.lowercased()
        var results: [SkillMatch] = []

        for skill in skills {
            var score: Double = 0

            // 1. 触发词精确匹配 → 权重 10（已在关键字匹配中覆盖）
            if skill.manifest.triggers.contains(where: { content.contains($0.lowercased()) }) {
                score += 10
            }

            // 2. 语义匹配 (embedding cos-sim) → 权重 0-5
            if let vectorSearch, let handler = await vectorSearch.embedHandler {
                let skillDesc: String = skill.manifest.description + " " + skill.manifest.tags.joined(separator: " ")
                if !skillDesc.trimmingCharacters(in: .whitespaces).isEmpty {
                    let texts: [String] = [request.content, skillDesc]
                    if let vectors = await handler(texts), vectors.count == 2 {
                        let sim: Float = VectorSearch.cosineSimilarity(vectors[0], vectors[1])
                        score += Double(sim) * 5
                    }
                }
            }

            // 3. 标签匹配 → 权重 2
            for tag in skill.manifest.tags where content.contains(tag.lowercased()) {
                score += 2
            }

            if score > 0 {
                results.append(SkillMatch(skill: skill, score: score))
            }
        }

        return results.sorted { $0.score > $1.score }
    }

    /// 向后兼容的纯关键字匹配
    public func matchByKeywords(for request: UserRequest) -> [SkillMatch] {
        let content: String = request.content.lowercased()
        return skills.compactMap { skill in
            var score: Double = 0
            if skill.manifest.triggers.contains(where: { content.contains($0.lowercased()) }) {
                score += 10
            }
            for tag in skill.manifest.tags where content.contains(tag.lowercased()) {
                score += 2
            }
            return score > 0 ? SkillMatch(skill: skill, score: score) : nil
        }.sorted { $0.score > $1.score }
    }

    public func count() -> Int {
        skills.count
    }

    public func remove(name: String) {
        skills.removeAll { $0.manifest.name == name }
    }

    public func removeAll() {
        skills.removeAll()
    }

    public func allSkills() -> [SkillMatch] {
        skills.map { SkillMatch(skill: $0, score: 0) }
    }

    // MARK: - File Scanning

    /// 扫描磁盘上的 skill 目录，加载所有 .skill.md 文件
    public func scan(from directory: URL) async throws -> [SkillManifest] {
        let fileManager: FileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        var manifests: [SkillManifest] = []
        let parser: SkillParser = SkillParser()

        // 收集所有 .skill.md 文件
        let files: [String] = (try? fileManager.subpathsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasSuffix(".skill.md") {
            let url: URL = directory.appendingPathComponent(file)
            guard let content: String = try? String(contentsOf: url, encoding: .utf8),
                let parsed: SkillContent = parser.parse(content)
            else { continue }
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
