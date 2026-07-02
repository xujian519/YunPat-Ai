import Foundation

/// 内存向量索引 — 无 SQLite 时的降级方案
///
/// 运行时扫描 vault 的 `Wiki/**/*.md`，按段落分块，用 ``EmbeddingProvider`` 现场编码。
/// 首次 `search` 前自动 `scan`（懒加载），后续复用。
///
/// 适用场景：
/// - 首次使用（无预构建索引文件）
/// - 用户自定义小 vault
/// - 单元测试
///
/// 性能：扫描 + 编码是一次性的（N 个 chunk × embedder 延迟），
/// 后续检索纯内存余弦相似度，适合 < 5000 chunk 的 vault。
public actor InMemoryVectorIndex: SemanticIndex {

    public let displayName: String = "InMemory (runtime scan)"
    public private(set) var isAvailable: Bool = false
    public private(set) var vectorCount: Int = 0

    private let vaultPath: URL
    private let embedder: EmbeddingProvider

    /// 内存条目：chunk 元数据 + 向量
    private struct Entry: Sendable {
        let chunkText: String
        let documentId: String
        let title: String
        let source: String
        let docType: String
        let module: String?
        let heading: String?
        let vector: [Float]
    }

    private var entries: [Entry] = []

    public init(vaultPath: URL, embedder: EmbeddingProvider) {
        self.vaultPath = vaultPath
        self.embedder = embedder
    }

    // MARK: - SemanticIndex

    public func search(
        queryEmbedding: [Float],
        topK: Int,
        minScore: Float,
        filter: IndexFilter?
    ) async throws -> [IndexHit] {
        if !isAvailable { try await scan() }
        guard isAvailable, !entries.isEmpty else { return [] }

        // 计算 query norm
        let qNorm = sqrt(queryEmbedding.map { $0 * $0 }.reduce(0, +))
        guard qNorm > 0 else { return [] }

        // 逐条余弦相似度 + topK 堆
        var scored: [(entry: Entry, score: Float)] = []
        scored.reserveCapacity(entries.count)

        for entry in entries {
            // 应用过滤
            if let filter, !matches(entry, filter) { continue }

            let dot = zip(queryEmbedding, entry.vector).map(*).reduce(0, +)
            // entry.vector 已归一化（embedder 保证），所以 cos = dot / qNorm
            let cos: Float = dot / qNorm
            if cos >= minScore {
                scored.append((entry, cos))
            }
        }

        return scored.sorted { $0.score > $1.score }
            .prefix(topK)
            .map { entry, score in
                IndexHit(
                    chunkText: entry.chunkText,
                    documentId: entry.documentId,
                    title: entry.title,
                    source: entry.source,
                    docType: entry.docType,
                    module: entry.module,
                    score: Double(score),
                    heading: entry.heading
                )
            }
    }

    // MARK: - Scan

    /// 扫描 vault，构建内存索引（首次 search 前自动调用）
    public func scan() async throws {
        entries.removeAll()
        let wikiDir = vaultPath.appendingPathComponent("Wiki")
        guard FileManager.default.fileExists(atPath: wikiDir.path) else {
            isAvailable = true  // 空索引也算可用
            return
        }

        // 递归遍历 Wiki/**/*.md
        let mdFiles: [URL] = collectMarkdownFiles(in: wikiDir)

        // 按模块（子目录名）分组
        for fileURL in mdFiles {
            let module: String? = moduleOf(fileURL, relativeTo: wikiDir)
            let content: String = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let title: String = extractTitle(from: content, fallback: fileURL.deletingPathExtension().lastPathComponent)
            let documentId: String = fileURL.deletingPathExtension().path
            let chunks = splitChunks(content: content)

            // 批量编码
            let chunkTexts = chunks.map { $0.text }
            let vectors: [[Float]]
            do {
                vectors = try await embedder.embed(chunkTexts)
            } catch {
                continue  // 跳过编码失败的文件
            }

            guard vectors.count == chunks.count else { continue }

            for (index, chunk) in chunks.enumerated() {
                entries.append(Entry(
                    chunkText: chunk.text,
                    documentId: documentId,
                    title: title,
                    source: "wiki",
                    docType: "concept",
                    module: module,
                    heading: chunk.heading,
                    vector: vectors[index]
                ))
            }
        }

        vectorCount = entries.count
        isAvailable = true
    }

    // MARK: - Helpers

    private func collectMarkdownFiles(in dir: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { url in
            guard let url = url as? URL,
                url.pathExtension == "md",
                url.lastPathComponent != "index.md"
            else { return nil }
            return url
        }
    }

    private func moduleOf(_ fileURL: URL, relativeTo wikiDir: URL) -> String? {
        let relative = fileURL.path.replacingOccurrences(of: wikiDir.path + "/", with: "")
        let components = relative.split(separator: "/")
        return components.count > 1 ? String(components[0]) : nil
    }

    private func extractTitle(from content: String, fallback: String) -> String {
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2))
            }
        }
        return fallback
    }

    /// 按段落分块（双换行分割），每块不超过 500 字符
    private func splitChunks(content: String) -> [(text: String, heading: String?)] {
        let paragraphs = content.components(separatedBy: "\n\n")
        var chunks: [(text: String, heading: String?)] = []
        var currentHeading: String?

        for para: String in paragraphs {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // 检测标题行
            if trimmed.hasPrefix("#") {
                let headingText = trimmed.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                currentHeading = headingText
                continue
            }

            // 长段落进一步切分
            if trimmed.count > 500 {
                let mid = trimmed.index(trimmed.startIndex, offsetBy: trimmed.count / 2)
                let searchRange = trimmed.range(of: "。", range: mid..<trimmed.endIndex)
                let splitPoint: String.Index = searchRange?.upperBound ?? mid
                chunks.append((String(trimmed[..<splitPoint]), currentHeading))
                chunks.append((String(trimmed[splitPoint...]), currentHeading))
            } else {
                chunks.append((trimmed, currentHeading))
            }
        }

        return chunks
    }

    private func matches(_ entry: Entry, _ filter: IndexFilter) -> Bool {
        if let domain = filter.domain, !domain.isEmpty {
            // InMemory 索引无 domain 概念，默认 patent
            if domain != "patent" { return false }
        }
        if let modules = filter.modules, !modules.isEmpty {
            guard let mod = entry.module, modules.contains(mod) else { return false }
        }
        if let docTypes = filter.docTypes, !docTypes.isEmpty {
            if !docTypes.contains(entry.docType) { return false }
        }
        return true
    }
}
