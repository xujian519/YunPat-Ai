import Foundation
import os
import SQLite3

/// SQLite 持久化 — 替代 JSON 文件的 MemoryStore
///
/// 设计 §6.8：每案件独立数据库，跨案件索引。
/// 使用系统 SQLite3 库（无外部依赖），线程安全 actor 封装。
public actor MemoryDatabase {  // swiftlint:disable:this type_body_length
    public static let shared: MemoryDatabase = MemoryDatabase()
    private let logger = Logger(subsystem: "com.yunpat", category: "MemoryDatabase")
    private nonisolated(unsafe) var db: OpaquePointer?
    private let dbPath: URL
    private let fileManager: FileManager

    private init() {
        self.fileManager = FileManager.default
        let home: URL = fileManager.homeDirectoryForCurrentUser
        let dir: URL = home.appendingPathComponent(".yunpat/memory")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.dbPath = dir.appendingPathComponent("memory.sqlite")
    }

    private func ensureDatabase() {
        guard db == nil else { return }
        openDatabase()
        createTables()
    }

    // MARK: - Database Lifecycle

    private func openDatabase() {
        guard
            sqlite3_open_v2(
                dbPath.path, &db,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                nil) == SQLITE_OK
        else {
            logger.error("Failed to open: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return
        }
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("PRAGMA foreign_keys=ON")
    }

    private func createTables() {
        exec(
            """
                CREATE TABLE IF NOT EXISTS ltm_items (
                    id TEXT PRIMARY KEY,
                    content TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    salience REAL NOT NULL DEFAULT 0.5,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)
        exec(
            """
                CREATE TABLE IF NOT EXISTS pinned_facts (
                    id TEXT PRIMARY KEY,
                    content TEXT NOT NULL,
                    salience REAL NOT NULL DEFAULT 0.5,
                    source_count INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL
                )
            """)
        exec(
            """
                CREATE TABLE IF NOT EXISTS case_contexts (
                    case_id TEXT PRIMARY KEY,
                    application_number TEXT,
                    technical_field TEXT NOT NULL DEFAULT '',
                    invention_points TEXT NOT NULL DEFAULT '[]',
                    key_references TEXT NOT NULL DEFAULT '[]',
                    open_issues TEXT NOT NULL DEFAULT '[]',
                    last_modified TEXT NOT NULL
                )
            """)
        exec(
            """
                CREATE TABLE IF NOT EXISTS episodes (
                    id TEXT PRIMARY KEY,
                    summary TEXT NOT NULL,
                    topics TEXT NOT NULL DEFAULT '[]',
                    entities TEXT NOT NULL DEFAULT '[]',
                    decisions TEXT NOT NULL DEFAULT '[]',
                    salience REAL NOT NULL DEFAULT 0.5,
                    created_at TEXT NOT NULL
                )
            """)
        exec("CREATE INDEX IF NOT EXISTS idx_ltm_salience ON ltm_items(salience DESC)")
        exec("CREATE INDEX IF NOT EXISTS idx_episodes_created ON episodes(created_at DESC)")
    }

    // MARK: - LTM Items

    public func saveLTMItem(_ item: LTMItem) async throws {
        ensureDatabase()
        guard let db else { return }
        let json = try JSONEncoder().encode(item)
        guard let jsonStr = String(data: json, encoding: .utf8) else { return }
        let iso: String = ISO8601DateFormatter().string(from: Date())
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db,
                """
                    INSERT OR REPLACE INTO ltm_items (id, content, kind, salience, created_at, updated_at)
                    VALUES (?, ?, ?, ?, COALESCE((SELECT created_at FROM ltm_items WHERE id=?), ?), ?)
                """, -1, &stmt, nil) == SQLITE_OK, let stmt
        else { throw dbError() }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, item.id.uuidString)
        bindText(stmt, 2, jsonStr)
        bindText(stmt, 3, "general")
        sqlite3_bind_double(stmt, 4, Double(item.salience))
        bindText(stmt, 5, item.id.uuidString)
        bindText(stmt, 6, iso)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError() }
    }

    public func loadAllLTMItems() async -> [LTMItem] {
        ensureDatabase()
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(db, "SELECT content FROM ltm_items ORDER BY salience DESC", -1, &stmt, nil) == SQLITE_OK,
            let stmt
        else { return [] }
        defer { sqlite3_finalize(stmt) }
        var items: [LTMItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let json = colText(stmt, 0), let data = json.data(using: .utf8),
                let item = try? JSONDecoder().decode(LTMItem.self, from: data)
            {  // swiftlint:disable:this opening_brace
                items.append(item)
            }
        }
        return items
    }

    public func deleteLTMItem(id: UUID) async {
        ensureDatabase()
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM ltm_items WHERE id=?", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id.uuidString)
        sqlite3_step(stmt)
    }

    // MARK: - Pinned Facts

    public func savePinnedFact(_ fact: PinnedFact) async throws {
        ensureDatabase()
        guard let db else { return }
        let json = try JSONEncoder().encode(fact)
        guard let jsonStr = String(data: json, encoding: .utf8) else { return }
        let pinnedSQL: String =
            "INSERT OR REPLACE INTO pinned_facts (id, content, salience, source_count, created_at) VALUES (?, ?, ?, ?, ?)"  // swiftlint:disable:this line_length
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db,
                pinnedSQL, -1, &stmt, nil) == SQLITE_OK, let stmt
        else { throw dbError() }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, fact.id.uuidString)
        bindText(stmt, 2, jsonStr)
        sqlite3_bind_double(stmt, 3, Double(fact.salience))
        sqlite3_bind_int64(stmt, 4, Int64(fact.sourceCount))
        bindText(stmt, 5, ISO8601DateFormatter().string(from: fact.createdAt))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError() }
    }

    public func loadAllPinnedFacts() async -> [PinnedFact] {
        ensureDatabase()
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(db, "SELECT content FROM pinned_facts ORDER BY salience DESC", -1, &stmt, nil)
                == SQLITE_OK, let stmt
        else { return [] }
        defer { sqlite3_finalize(stmt) }
        var facts: [PinnedFact] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let json = colText(stmt, 0), let data = json.data(using: .utf8),
                let fact = try? JSONDecoder().decode(PinnedFact.self, from: data)
            {  // swiftlint:disable:this opening_brace
                facts.append(fact)
            }
        }
        return facts
    }

    public func deletePinnedFact(id: UUID) async {
        ensureDatabase()
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM pinned_facts WHERE id=?", -1, &stmt, nil) == SQLITE_OK, let stmt
        else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id.uuidString)
        sqlite3_step(stmt)
    }

    // MARK: - Case Context

    public func saveCaseContext(_ ctx: CaseContext) async throws {
        ensureDatabase()
        guard let db else { return }
        let invJSON: Data = try JSONEncoder().encode(ctx.inventionPoints)
        let refJSON: Data = try JSONEncoder().encode(ctx.keyReferences)
        let issuesJSON: Data = try JSONEncoder().encode(ctx.openIssues)
        let ctxSQL: String =
            "INSERT OR REPLACE INTO case_contexts (case_id, application_number, technical_field, invention_points, key_references, open_issues, last_modified) VALUES (?, ?, ?, ?, ?, ?, ?)"  // swiftlint:disable:this line_length
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db,
                ctxSQL, -1, &stmt, nil) == SQLITE_OK, let stmt
        else { throw dbError() }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, ctx.caseId)
        bindText(stmt, 2, ctx.applicationNumber)
        bindText(stmt, 3, ctx.technicalField)
        bindText(stmt, 4, String(data: invJSON, encoding: .utf8))
        bindText(stmt, 5, String(data: refJSON, encoding: .utf8))
        bindText(stmt, 6, String(data: issuesJSON, encoding: .utf8))
        bindText(stmt, 7, ISO8601DateFormatter().string(from: ctx.lastModified))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError() }
    }

    public func loadCaseContext(_ caseId: String) async -> CaseContext? {
        ensureDatabase()
        guard let db else { return nil }
        let loadSQL: String =
            "SELECT application_number, technical_field, invention_points, key_references, open_issues, last_modified FROM case_contexts WHERE case_id=?"  // swiftlint:disable:this line_length
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db,
                loadSQL, -1, &stmt, nil) == SQLITE_OK, let stmt
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, caseId)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let appNum = colText(stmt, 0)
        let techField: String = colText(stmt, 1) ?? ""
        let invPoints: [String] = colJSON(stmt, 2) ?? []
        let keyRefs: [String] = colJSON(stmt, 3) ?? []
        let issues: [String] = colJSON(stmt, 4) ?? []
        return CaseContext(
            caseId: caseId, applicationNumber: appNum, technicalField: techField,
            inventionPoints: invPoints, keyReferences: keyRefs, openIssues: issues)
    }

    // MARK: - Episodes

    public func saveEpisode(_ episode: Episode) async throws {
        ensureDatabase()
        guard let db else { return }
        let json = try JSONEncoder().encode(episode)
        guard let jsonStr = String(data: json, encoding: .utf8) else { return }
        let topicsData = try JSONEncoder().encode(episode.topics)
        let entitiesData = try JSONEncoder().encode(episode.entities)
        let decisionsData = try JSONEncoder().encode(episode.decisions)
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db,
                """
                    INSERT OR REPLACE INTO episodes (id, summary, topics, entities, decisions, salience, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, -1, &stmt, nil) == SQLITE_OK, let stmt
        else { throw dbError() }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, episode.id.uuidString)
        bindText(stmt, 2, jsonStr)
        bindText(stmt, 3, String(data: topicsData, encoding: .utf8))
        bindText(stmt, 4, String(data: entitiesData, encoding: .utf8))
        bindText(stmt, 5, String(data: decisionsData, encoding: .utf8))
        sqlite3_bind_double(stmt, 6, Double(episode.salience))
        bindText(stmt, 7, ISO8601DateFormatter().string(from: Date()))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError() }
    }

    public func loadAllEpisodes() async -> [Episode] {
        ensureDatabase()
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(db, "SELECT summary FROM episodes ORDER BY created_at DESC", -1, &stmt, nil)
                == SQLITE_OK, let stmt
        else { return [] }
        defer { sqlite3_finalize(stmt) }
        var episodes: [Episode] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let json = colText(stmt, 0), let data = json.data(using: .utf8),
                let episode = try? JSONDecoder().decode(Episode.self, from: data)
            {  // swiftlint:disable:this opening_brace
                episodes.append(episode)
            }
        }
        return episodes
    }

    public func deleteEpisode(id: UUID) async {
        ensureDatabase()
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM episodes WHERE id=?", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id.uuidString)
        sqlite3_step(stmt)
    }

    // MARK: - Maintenance

    public func clearAll() async {
        ensureDatabase()
        exec("DELETE FROM ltm_items")
        exec("DELETE FROM pinned_facts")
        exec("DELETE FROM case_contexts")
        exec("DELETE FROM episodes")
    }

    public var storageSize: UInt64 {
        (try? fileManager.attributesOfItem(atPath: dbPath.path)[FileAttributeKey.size] as? UInt64) ?? 0
    }

    public func vacuum() async {
        ensureDatabase()
        exec("VACUUM")
    }

    // MARK: - Recent / Batch

    public func loadRecentEpisodes(limit: Int = 20) async -> [Episode] {
        ensureDatabase()
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db,
                "SELECT summary FROM episodes ORDER BY created_at DESC LIMIT ?",
                -1, &stmt, nil) == SQLITE_OK, let stmt
        else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(limit))
        var episodes: [Episode] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let json = colText(stmt, 0), let data = json.data(using: .utf8),
                let episode = try? JSONDecoder().decode(Episode.self, from: data) {
                episodes.append(episode)
            }
        }
        return episodes
    }

    public func deleteEpisodes(before date: Date) async {
        ensureDatabase()
        guard let db else { return }
        let iso = ISO8601DateFormatter().string(from: date)
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(db, "DELETE FROM episodes WHERE created_at < ?", -1, &stmt, nil) == SQLITE_OK,
            let stmt
        else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, iso)
        sqlite3_step(stmt)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - SQLite Helpers

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let val = value {
            sqlite3_bind_text(stmt, index, (val as NSString).utf8String, -1, Self.SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func colText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cstr)
    }

    private func colJSON<T: Decodable>(_ stmt: OpaquePointer, _ index: Int32) -> T? {
        guard let json = colText(stmt, index), let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func dbError() -> Error {
        let msg: String = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
        return NSError(
            domain: "YunPatCore.MemoryDatabase", code: Int(sqlite3_errcode(db)),
            userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
