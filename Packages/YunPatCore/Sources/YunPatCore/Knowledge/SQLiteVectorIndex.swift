import Accelerate
import Foundation
import SQLite3

/// SQLite 向量索引 — 对接 XiaoNuo Agent `@nuo/knowledge` schema，两阶段零拷贝检索
///
/// 只读消费 `embeddings` + `chunks` + `documents` 三表。
/// 向量格式：Float32 little-endian BLOB，1024 维（bge-m3）。
///
/// 两阶段检索（零拷贝优化）：
/// 1. **扫描阶段** — 只读 vector BLOB 指针 + norm，用 vDSP 直接做 dot product（不拷贝），筛出 topK chunk_id
/// 2. **文本阶段** — 用 WHERE chunk_id IN (...) 批量查询 topK 的文本内容
///
/// 性能（Apple Silicon，56K 向量）：~30-50ms
public final class SQLiteVectorIndex: @unchecked Sendable {

    public let displayName: String
    public private(set) var isAvailable: Bool = false
    public private(set) var vectorCount: Int = 0

    private let dbPath: URL
    private var db: OpaquePointer?
    private let dimension: Int = 1024
    private let pageSize: Int = 5000

    // Prepared statements
    private var countStmt: OpaquePointer?
    private var scanStmt: OpaquePointer?
    private var scanDomainStmt: OpaquePointer?
    private var textStmt: OpaquePointer?
    private let scanLock: NSLock = NSLock()

    /// SQLITE_TRANSIENT — 让 SQLite 在 bind_text 时拷贝字符串
    private let sqliteTransient = unsafeBitCast(
        -1, to: sqlite3_destructor_type.self
    )

    public init(dbPath: URL) throws {
        self.dbPath = dbPath
        self.displayName = "SQLite: \(dbPath.lastPathComponent)"

        let openFlags: Int32 = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let openResult: Int32 = sqlite3_open_v2(dbPath.path, &db, openFlags, nil)
        guard openResult == SQLITE_OK else {
            let errMsg: String = String(cString: sqlite3_errmsg(db))
            throw SQLiteIndexError.openFailed(errMsg)
        }

        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA query_only=1;", nil, nil, nil)

        try verifySchema()
        try prepareStatements()
    }

    deinit {
        sqlite3_finalize(countStmt)
        sqlite3_finalize(scanStmt)
        sqlite3_finalize(scanDomainStmt)
        sqlite3_finalize(textStmt)
        sqlite3_close(db)
    }

    // MARK: - Schema Verification

    private func verifySchema() throws {
        let checkSQL: String = """
            SELECT name FROM sqlite_master \
            WHERE type='table' AND name='embeddings'
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, checkSQL, -1, &stmt, nil) == SQLITE_OK,
            sqlite3_step(stmt) == SQLITE_ROW
        else {
            sqlite3_finalize(stmt)
            isAvailable = false
            vectorCount = 0
            return
        }
        sqlite3_finalize(stmt)

        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM embeddings", -1, &countStmt, nil) == SQLITE_OK,
            sqlite3_step(countStmt) == SQLITE_ROW
        else {
            isAvailable = false
            vectorCount = 0
            return
        }
        vectorCount = Int(sqlite3_column_int64(countStmt, 0))
        isAvailable = vectorCount > 0
    }

    // MARK: - Prepared Statements

    /// 第一阶段：只读 vector + norm + 过滤字段（不 JOIN chunks，避免读取大文本）
    private static let scanSQL: String = """
        SELECT e.id, e.chunk_id, e.document_id, e.vector, e.norm, d.module, d.doc_type, d.domain
        FROM embeddings e
        JOIN documents d ON e.document_id = d.id
        WHERE e.id > ?
        ORDER BY e.id
        LIMIT ?
        """

    private static let scanDomainSQL: String = """
        SELECT e.id, e.chunk_id, e.document_id, e.vector, e.norm, d.module, d.doc_type, d.domain
        FROM embeddings e
        JOIN documents d ON e.document_id = d.id
        WHERE e.id > ? AND d.domain = ?
        ORDER BY e.id
        LIMIT ?
        """

    /// 第二阶段：批量查询 topK 的文本内容
    private static let textSQLPrefix: String = """
        SELECT c.id, c.content, c.heading, d.id, d.title, d.source, d.doc_type, d.module
        FROM chunks c
        JOIN documents d ON c.document_id = d.id
        WHERE c.id IN
        """

    private func prepareStatements() throws {
        guard isAvailable else { return }
        if sqlite3_prepare_v2(db, Self.scanSQL, -1, &scanStmt, nil) != SQLITE_OK {
            throw SQLiteIndexError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        if sqlite3_prepare_v2(db, Self.scanDomainSQL, -1, &scanDomainStmt, nil) != SQLITE_OK {
            throw SQLiteIndexError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - SemanticIndex

    /// 向量检索（带过滤）
    ///
    /// 两阶段检索：
    /// 1. 扫描阶段 — 零拷贝读 vector BLOB，vDSP dot product 筛 topK
    /// 2. 文本阶段 — WHERE chunk_id IN (...) 批量查询文本内容
    /// - Parameters:
    ///   - queryEmbedding: 查询向量（须为 1024 维）
    ///   - topK: 返回上限
    ///   - minScore: 余弦相似度阈值（默认 0.3）
    ///   - filter: 按 domain/module/docType 过滤
    public func search(
        queryEmbedding: [Float],
        topK: Int,
        minScore: Float,
        filter: IndexFilter?
    ) async throws -> [IndexHit] {
        guard isAvailable, queryEmbedding.count == dimension else { return [] }

        var queryNorm: Float = 0
        queryEmbedding.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_svesq(base, 1, &queryNorm, vDSP_Length(dimension))
        }
        queryNorm = sqrt(queryNorm)
        guard queryNorm > 0 else { return [] }

        // ── 第一阶段：零拷贝向量扫描 + topK ──
        let heap: [ScoredChunk] = scanVectors(
            queryEmbedding: queryEmbedding, queryNorm: queryNorm,
            filter: filter, topK: topK, minScore: minScore
        )
        if heap.isEmpty { return [] }

        // ── 第二阶段：批量查询 topK 的文本内容 ──
        let sortedHeap: [ScoredChunk] = heap.sorted { $0.score > $1.score }
        let chunkIds: [Int] = sortedHeap.map { $0.chunkId }
        let textMap: [Int: ChunkText] = fetchChunkTexts(chunkIds: chunkIds)

        return sortedHeap.compactMap { entry -> IndexHit? in
            guard let text: ChunkText = textMap[entry.chunkId] else { return nil }
            return IndexHit(
                chunkText: text.content,
                documentId: entry.documentId,
                title: text.title,
                source: text.source,
                docType: text.docType,
                module: text.module,
                score: Double(entry.score),
                heading: text.heading
            )
        }
    }

    // MARK: - Scan Phase

    private struct ScoredChunk: Sendable {
        let score: Float
        let chunkId: Int
        let documentId: String
    }

    private nonisolated func scanVectors(
        queryEmbedding: [Float], queryNorm: Float,
        filter: IndexFilter?, topK: Int, minScore: Float
    ) -> [ScoredChunk] {
        scanLock.lock()
        defer { scanLock.unlock() }
        let useDomainFilter: Bool = filter?.domain != nil && !(filter?.domain?.isEmpty ?? true)
        let stmt: OpaquePointer? = useDomainFilter ? scanDomainStmt : scanStmt

        var heap: [ScoredChunk] = []
        var lastId: Int64 = 0

        queryEmbedding.withUnsafeBufferPointer { queryBuf in
            guard let queryBase: UnsafePointer<Float> = queryBuf.baseAddress else { return }

            while true {
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, lastId)
                if useDomainFilter, let domain: String = filter?.domain {
                    domain.withCString { cStr in
                        sqlite3_bind_text(stmt, 2, cStr, -1, sqliteTransient)
                    }
                    sqlite3_bind_int64(stmt, 3, Int64(pageSize))
                } else {
                    sqlite3_bind_int64(stmt, 2, Int64(pageSize))
                }

                var rowCount: Int = 0
                while sqlite3_step(stmt) == SQLITE_ROW {
                    rowCount += 1
                    lastId = sqlite3_column_int64(stmt, 0)
                    let chunkId: Int = Int(sqlite3_column_int64(stmt, 1))
                    let documentId: String = columnText(stmt, 2)

                    guard let blobPtr: UnsafeRawPointer = sqlite3_column_blob(stmt, 3) else { continue }
                    let blobBytes: Int = Int(sqlite3_column_bytes(stmt, 3))
                    guard blobBytes == dimension * MemoryLayout<Float>.size else { continue }

                    let vecPtr: UnsafePointer<Float> = blobPtr.assumingMemoryBound(to: Float.self)
                    var dot: Float = 0
                    vDSP_dotpr(queryBase, 1, vecPtr, 1, &dot, vDSP_Length(dimension))

                    let norm: Float = Float(sqlite3_column_double(stmt, 4))
                    guard norm > 0 else { continue }
                    let cos: Float = dot / (queryNorm * norm)
                    guard cos >= minScore else { continue }

                    if let filter, !matchesFilter(stmt, filter) { continue }

                    if heap.count < topK {
                        heap.append(ScoredChunk(score: cos, chunkId: chunkId, documentId: documentId))
                        siftUp(&heap)
                    } else if cos > heap[0].score {
                        heap[0] = ScoredChunk(score: cos, chunkId: chunkId, documentId: documentId)
                        siftDown(&heap, 0)
                    }
                }

                if rowCount < pageSize { break }
            }
        }

        return heap
    }

    // MARK: - Second Phase: Text Fetch

    private struct ChunkText: Sendable {
        let content: String
        let heading: String?
        let title: String
        let source: String
        let docType: String
        let module: String?
    }

    private func fetchChunkTexts(chunkIds: [Int]) -> [Int: ChunkText] {
        let placeholders: String = chunkIds.map { _ in "?" }.joined(separator: ",")
        let sql: String = "\(Self.textSQLPrefix) (\(placeholders))"

        var localStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &localStmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(localStmt) }

        for (idx, chunkId) in chunkIds.enumerated() {
            sqlite3_bind_int64(localStmt, Int32(idx + 1), Int64(chunkId))
        }

        var result: [Int: ChunkText] = [:]
        while sqlite3_step(localStmt) == SQLITE_ROW {
            let chunkId: Int = Int(sqlite3_column_int64(localStmt, 0))
            result[chunkId] = ChunkText(
                content: columnText(localStmt, 1),
                heading: columnTextOptional(localStmt, 2),
                title: columnText(localStmt, 4),
                source: columnText(localStmt, 5),
                docType: columnText(localStmt, 6),
                module: columnTextOptional(localStmt, 7)
            )
        }
        return result
    }
}

// MARK: - Helpers Extension

extension SQLiteVectorIndex {
    private func matchesFilter(_ stmt: OpaquePointer?, _ filter: IndexFilter) -> Bool {
        if let modules: Set<String> = filter.modules, !modules.isEmpty {
            let module: String = columnText(stmt, 5)
            guard modules.contains(module) else { return false }
        }
        if let docTypes: Set<String> = filter.docTypes, !docTypes.isEmpty {
            let docType: String = columnText(stmt, 6)
            guard docTypes.contains(docType) else { return false }
        }
        return true
    }

    private func columnText(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        if let ptr = sqlite3_column_text(stmt, col) {
            return String(cString: ptr)
        }
        return ""
    }

    private func columnTextOptional(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        if let ptr = sqlite3_column_text(stmt, col) {
            let str = String(cString: ptr)
            return str.isEmpty ? nil : str
        }
        return nil
    }

    private func siftUp(_ heap: inout [ScoredChunk]) {
        var idx: Int = heap.count - 1
        while idx > 0 {
            let parentIdx: Int = (idx - 1) >> 1
            if heap[idx].score >= heap[parentIdx].score { break }
            heap.swapAt(idx, parentIdx)
            idx = parentIdx
        }
    }

    private func siftDown(_ heap: inout [ScoredChunk], _ startIdx: Int) {
        var idx: Int = startIdx
        let heapCount: Int = heap.count
        while true {
            var smallest: Int = idx
            let left: Int = (idx << 1) + 1
            let right: Int = left + 1
            if left < heapCount, heap[left].score < heap[smallest].score { smallest = left }
            if right < heapCount, heap[right].score < heap[smallest].score { smallest = right }
            if smallest == idx { break }
            heap.swapAt(idx, smallest)
            idx = smallest
        }
    }
}

// MARK: - SemanticIndex Conformance

extension SQLiteVectorIndex: SemanticIndex {}

// MARK: - Errors

public enum SQLiteIndexError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let detail):
            return "SQLite 数据库打开失败: \(detail)"
        case .prepareFailed(let detail):
            return "SQL 预处理失败: \(detail)"
        }
    }
}
