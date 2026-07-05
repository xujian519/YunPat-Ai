import Foundation
import Testing
import SQLite3

@testable import YunPatCore

struct LegacySemanticIndexTests {

    private func createTestIndex() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db else {
            throw TestError("Failed to create test DB")
        }
        defer { sqlite3_close(db) }

        let createSQL = """
            CREATE TABLE chunks (
                chunk_id TEXT PRIMARY KEY,
                file_path TEXT NOT NULL,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                chunk_index INTEGER NOT NULL DEFAULT 0,
                embedding BLOB NOT NULL,
                embedding_dim INTEGER NOT NULL
            );
            """
        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            throw TestError("Failed to create table: \(String(cString: sqlite3_errmsg(db)))")
        }

        // Insert test vectors: 1024-dim float32 BLOBs
        let dim = 1024
        let insertSQL = "INSERT INTO chunks (chunk_id, file_path, title, content, chunk_index, embedding, embedding_dim) VALUES (?, ?, ?, ?, ?, ?, ?)"
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
            throw TestError("Failed to prepare insert")
        }
        defer { sqlite3_finalize(insertStmt) }

        // Insert 3 chunks with known vectors
        let chunks: [(id: String, path: String, title: String, content: String, vec: [Float])] = [
            ("c1", "/Wiki/专利实务/创造性.md", "创造性三步法", "三步法是判断创造性的核心方法", vector([1, 0, 0])),
            ("c2", "/Wiki/审查指南/审查.md", "审查指南", "审查指南规定了审查程序", vector([0, 1, 0])),
            ("c3", "/Wiki/专利侵权/侵权.md", "侵权判定", "全面覆盖原则是侵权判定的基本原则", vector([0, 0, 1])),
        ]

        for chunk in chunks {
            sqlite3_bind_text(insertStmt, 1, chunk.id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(insertStmt, 2, chunk.path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(insertStmt, 3, chunk.title, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(insertStmt, 4, chunk.content, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int64(insertStmt, 5, 0)
            let data = Data(bytes: chunk.vec, count: dim * 4)
            try data.withUnsafeBytes { buf in
                guard let ptr = buf.baseAddress else { throw TestError("No buffer") }
                sqlite3_bind_blob(insertStmt, 6, ptr, Int32(dim * 4), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            sqlite3_bind_int64(insertStmt, 7, Int64(dim))
            guard sqlite3_step(insertStmt) == SQLITE_DONE else {
                throw TestError("Insert failed: \(String(cString: sqlite3_errmsg(db)))")
            }
            sqlite3_reset(insertStmt)
        }

        return tmp
    }

    @Test func isAvailable_returnsTrue() async throws {
        let url = try createTestIndex()
        defer { try? FileManager.default.removeItem(at: url) }

        let index = LegacySemanticIndex(dbPath: url)
        let available = await index.isAvailable
        #expect(available)
    }

    @Test func vectorCount_returnsCorrectCount() async throws {
        let url = try createTestIndex()
        defer { try? FileManager.default.removeItem(at: url) }

        let index = LegacySemanticIndex(dbPath: url)
        let count = await index.vectorCount
        #expect(count == 3)
    }

    @Test func search_returnsTopK() async throws {
        let url = try createTestIndex()
        defer { try? FileManager.default.removeItem(at: url) }

        let index = LegacySemanticIndex(dbPath: url)
        let queryEmbedding: [Float] = vector([1, 0.5, 0.2])
        let hits = try await index.search(queryEmbedding: queryEmbedding, topK: 2, minScore: 0.1)

        #expect(hits.count == 2)
        #expect(hits[0].title == "创造性三步法")
        #expect(hits[0].module == "专利实务")
        #expect(hits[0].docType == "concept")
        #expect(hits[0].score > 0.8)
    }

    @Test func search_filterByModule() async throws {
        let url = try createTestIndex()
        defer { try? FileManager.default.removeItem(at: url) }

        let index = LegacySemanticIndex(dbPath: url)
        let queryEmbedding: [Float] = vector([1, 0, 0])
        let filter = IndexFilter(modules: ["审查指南"])
        let hits = try await index.search(queryEmbedding: queryEmbedding, topK: 5, minScore: 0.0, filter: filter)

        #expect(hits.count == 1)
        #expect(hits[0].title == "审查指南")
    }

    @Test func search_emptyIndex_returnsEmpty() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            return
        }
        sqlite3_close(db)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let index = LegacySemanticIndex(dbPath: tmp)
        let available = await index.isAvailable
        #expect(!available)
    }

    @Test func search_minScoreFilters() async throws {
        let url = try createTestIndex()
        defer { try? FileManager.default.removeItem(at: url) }

        let index = LegacySemanticIndex(dbPath: url)
        let queryEmbedding: [Float] = vector([1, 0, 0])
        // high minScore should exclude all but the exact match
        let hits = try await index.search(queryEmbedding: queryEmbedding, topK: 5, minScore: 0.95)

        #expect(hits.count == 1)
        #expect(hits[0].title == "创造性三步法")
    }

    @Test func search_unknownModule_infersCorrectly() async throws {
        let url = try createTestIndex()
        defer { try? FileManager.default.removeItem(at: url) }

        // Insert a chunk with unknown path
        var db: OpaquePointer?
        sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        let insertSQL = "INSERT INTO chunks VALUES ('c4', '/Wiki/方法论/方法.md', '方法论', '内容', 0, ?, 1024)"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil)
        let vec = vector([0.5, 0.5, 0])
        let data = Data(bytes: vec, count: 1024 * 4)
        try data.withUnsafeBytes { buf in
            sqlite3_bind_blob(stmt, 1, buf.baseAddress, Int32(1024 * 4), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        sqlite3_close(db)

        let index = LegacySemanticIndex(dbPath: url)
        let hits = try await index.search(queryEmbedding: vector([0.5, 0.5, 0]), topK: 5, minScore: 0.1)

        let methodHit = hits.first { $0.title == "方法论" }
        #expect(methodHit != nil)
        #expect(methodHit?.module == "其他")
        #expect(methodHit?.source == "wiki")
    }
}

// Helper: Create a 1024-dim vector from a shorter seed
private func vector(_ seed: [Float]) -> [Float] {
    var v = [Float](repeating: 0, count: 1024)
    for i in 0..<min(seed.count, 1024) {
        v[i] = seed[i]
    }
    return v
}

private struct TestError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
