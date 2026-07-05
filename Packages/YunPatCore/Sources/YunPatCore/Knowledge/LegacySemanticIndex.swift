import Accelerate
import Foundation
import SQLite3

/// 适配现有 `.yunpat-semantic-index.sqlite` schema 的语义索引
///
/// 该索引由 XiaoNuo Agent 工具链生成，schema 与 `SQLiteVectorIndex` 不同：
/// ```sql
/// chunks(chunk_id TEXT PK, file_path TEXT, title TEXT, content TEXT,
///        chunk_index INT, embedding BLOB, embedding_dim INT)
/// ```
///
/// `LegacySemanticIndex` 以只读方式打开该文件，通过 vDSP 加速的余弦相似度做全表扫描。
/// 4,800+ chunks 的检索耗时约 20-50ms（Apple Silicon）。
public final class LegacySemanticIndex: @unchecked Sendable {

    public let displayName: String
    public private(set) var isAvailable: Bool = false
    public private(set) var vectorCount: Int = 0

    private let dbPath: URL
    private var db: OpaquePointer?
    private let dimension: Int = 1024

    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(dbPath: URL) {
        self.dbPath = dbPath
        self.displayName = "Legacy: \(dbPath.lastPathComponent)"
        openDatabase()
    }

    deinit {
        sqlite3_close(db)
    }

    private func openDatabase() {
        var handle: OpaquePointer?
        let flags: Int32 = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbPath.path, &handle, flags, nil) == SQLITE_OK,
              let handle else {
            isAvailable = false
            return
        }
        db = handle
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA query_only=1;", nil, nil, nil)
        checkSchema()
    }

    private func checkSchema() {
        guard let db else { isAvailable = false; return }
        var stmt: OpaquePointer?
        let sql: String = "SELECT name FROM sqlite_master WHERE type='table' AND name='chunks'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            sqlite3_finalize(stmt)
            isAvailable = false
            return
        }
        sqlite3_finalize(stmt)

        var countStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM chunks", -1, &countStmt, nil) == SQLITE_OK,
              sqlite3_step(countStmt) == SQLITE_ROW else {
            sqlite3_finalize(countStmt)
            isAvailable = false
            return
        }
        vectorCount = Int(sqlite3_column_int64(countStmt, 0))
        sqlite3_finalize(countStmt)
        isAvailable = vectorCount > 0
    }

    /// 从 file_path 推断 module
    private func inferModule(from filePath: String) -> String? {
        if filePath.contains("/Wiki/专利实务/") { return "专利实务" }
        if filePath.contains("/Wiki/审查指南/") { return "审查指南" }
        if filePath.contains("/Wiki/专利侵权/") { return "专利侵权" }
        if filePath.contains("/Wiki/专利判决/") { return "专利判决" }
        if filePath.contains("/Wiki/复审无效/") { return "复审无效" }
        if filePath.contains("/Wiki/法律法规/") { return "法律法规" }
        if filePath.contains("/Wiki/书籍/") { return "书籍" }
        if filePath.contains("/Wiki/个人笔记/") { return "个人笔记" }
        if filePath.contains("/Wiki/") { return "其他" }
        if filePath.contains("/Raw/") {
            if filePath.contains("审查指南") { return "审查指南" }
            if filePath.contains("判决") { return "专利判决" }
            if filePath.contains("复审") || filePath.contains("无效") { return "复审无效" }
        }
        if filePath.contains("/方法论/") { return "方法论" }
        return nil
    }

    /// 从 file_path 推断 docType
    private func inferDocType(from filePath: String) -> String {
        if filePath.contains("/审查指南/") { return "guideline_rule" }
        if filePath.contains("/法律法规/") { return "law_article" }
        if filePath.contains("/专利判决/") { return "judgment" }
        if filePath.contains("/复审无效/") { return "reexamination" }
        if filePath.contains("/专利侵权/") { return "infringement_guide" }
        if filePath.contains("/版权/") { return "copyright_guide" }
        if filePath.contains("/商标/") { return "trademark_guide" }
        return "concept"
    }

    /// 从 file_path 推断 source
    private func inferSource(from filePath: String) -> String {
        if filePath.contains("/Raw/") { return "raw" }
        if filePath.contains("/Wiki/") { return "wiki" }
        return "knowledge"
    }

    /// 从 file_path 提取 documentId（去掉根路径前缀后取相对路径）
    private func extractDocumentId(from filePath: String) -> String {
        if let range = filePath.range(of: "/Wiki/") ?? filePath.range(of: "/Raw/") {
            return String(filePath[range.lowerBound...])
        }
        let url = URL(fileURLWithPath: filePath)
        return url.deletingPathExtension().lastPathComponent
    }
}

// MARK: - SemanticIndex

extension LegacySemanticIndex: SemanticIndex {

    // swiftlint:disable:next function_body_length
    public func search(
        queryEmbedding: [Float],
        topK: Int,
        minScore: Float,
        filter: IndexFilter?
    ) async throws -> [IndexHit] {
        guard isAvailable, let db, queryEmbedding.count == dimension else { return [] }

        var queryNorm: Float = 0
        queryEmbedding.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_svesq(base, 1, &queryNorm, vDSP_Length(dimension))
        }
        queryNorm = sqrt(queryNorm)
        guard queryNorm > 0 else { return [] }

        let sql: String = """
            SELECT chunk_id, file_path, title, content, chunk_index, embedding, embedding_dim
            FROM chunks
            ORDER BY chunk_index
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var heap = MinHeap<ScoredEntry>(capacity: topK)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let chunkId = String(cString: sqlite3_column_text(stmt, 0))
            let filePath = String(cString: sqlite3_column_text(stmt, 1))
            let title = String(cString: sqlite3_column_text(stmt, 2))
            let content = String(cString: sqlite3_column_text(stmt, 3))
            _ = sqlite3_column_int64(stmt, 4)
            let dim = Int(sqlite3_column_int64(stmt, 6))
            guard dim == dimension else { continue }

            guard let blobPtr = sqlite3_column_blob(stmt, 5) else { continue }
            let vecPtr = blobPtr.bindMemory(to: Float.self, capacity: dimension)

            var dot: Float = 0
            queryEmbedding.withUnsafeBufferPointer { qPtr in
                guard let qBase = qPtr.baseAddress else { return }
                vDSP_dotpr(qBase, 1, vecPtr, 1, &dot, vDSP_Length(dimension))
            }

            var normSq: Float = 0
            vDSP_svesq(vecPtr, 1, &normSq, vDSP_Length(dimension))
            let vecNorm = sqrt(normSq)
            guard vecNorm > 0 else { continue }

            let score: Float = dot / (queryNorm * vecNorm)
            guard score >= minScore else { continue }

            let candidateModule = inferModule(from: filePath)

            if let filter {
                if let modules = filter.modules, let mod = candidateModule, !modules.contains(mod) { continue }
                if let docTypes = filter.docTypes, !docTypes.contains(inferDocType(from: filePath)) { continue }
            }

            let entry = ScoredEntry(
                chunkId: chunkId,
                filePath: filePath,
                title: title,
                content: content,
                module: candidateModule,
                docType: inferDocType(from: filePath),
                source: inferSource(from: filePath)
            )
            heap.insert(entry, score: score, maxSize: topK)
        }

        return heap.sorted().map { item in
            IndexHit(
                chunkText: item.item.content,
                documentId: item.item.filePath,
                title: item.item.title,
                source: item.item.source,
                docType: item.item.docType,
                module: item.item.module,
                score: Double(item.score),
                heading: item.item.title
            )
        }
    }
}

// MARK: - Min-Heap (bounded, for top-K)

private struct ScoredEntry: Sendable {
    let chunkId: String
    let filePath: String
    let title: String
    let content: String
    let module: String?
    let docType: String
    let source: String
}

private struct MinHeap<T: Sendable> {
    private var elements: [(item: T, score: Float)] = []

    init(capacity: Int) {
        elements.reserveCapacity(capacity + 1)
    }

    mutating func insert(_ item: T, score: Float, maxSize: Int) {
        elements.append((item, score))
        siftUp(from: elements.count - 1)
        if elements.count > maxSize {
            elements.swapAt(0, elements.count - 1)
            elements.removeLast()
            siftDown(from: 0)
        }
    }

    mutating func siftUp(from index: Int) {
        var child: Int = index
        while child > 0 {
            let parent: Int = (child - 1) / 2
            if elements[child].score >= elements[parent].score { break }
            elements.swapAt(child, parent)
            child = parent
        }
    }

    mutating func siftDown(from index: Int) {
        var parent: Int = index
        let count: Int = elements.count
        while true {
            let left: Int = 2 * parent + 1
            let right: Int = 2 * parent + 2
            var smallest: Int = parent
            if left < count, elements[left].score < elements[smallest].score { smallest = left }
            if right < count, elements[right].score < elements[smallest].score { smallest = right }
            if smallest == parent { break }
            elements.swapAt(parent, smallest)
            parent = smallest
        }
    }

    func sorted() -> [(item: T, score: Float)] {
        elements.sorted { $0.score > $1.score }
    }
}
