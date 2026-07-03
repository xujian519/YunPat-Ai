import Foundation
import SQLite3

/// 结构化案件数据库 — 每案件独立 SQLite 存储权利要求树、对比文件矩阵、审查意见逐条
///
/// 设计 §1 用户数据目录：~/.yunpat/memory/cases/{case-id}.sqlite
/// 每案件独立 SQLite 文件，支持 SQLCipher 可选加密（通过 FileVault）
public actor CaseDatabase {  // swiftlint:disable:this type_body_length
    public static let shared: CaseDatabase = CaseDatabase()
    private let fileManager: FileManager
    private let baseDir: URL

    private init() {
        self.fileManager = FileManager.default
        let home: URL = fileManager.homeDirectoryForCurrentUser
        self.baseDir = home.appendingPathComponent(".yunpat/memory/cases")
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    // MARK: - Database Connection

    private func openDB(for caseId: String) -> OpaquePointer? {
        guard isSafeCaseId(caseId) else { return nil }
        let dir: URL = baseDir.appendingPathComponent(caseId)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let path: String = dir.appendingPathComponent("case.sqlite").path
        var db: OpaquePointer?
        guard
            sqlite3_open_v2(
                path, &db,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                nil) == SQLITE_OK, let db
        else { return nil }
        exec(db, "PRAGMA journal_mode=WAL")
        exec(db, "PRAGMA foreign_keys=ON")
        createTables(db)
        return db
    }

    private func createTables(_ db: OpaquePointer) {
        exec(
            db,
            """
                CREATE TABLE IF NOT EXISTS claims (
                    id TEXT PRIMARY KEY,
                    case_id TEXT NOT NULL,
                    number TEXT NOT NULL,
                    text TEXT NOT NULL,
                    category TEXT NOT NULL,
                    parent_number TEXT,
                    created_at TEXT NOT NULL
                )
            """)
        exec(
            db,
            """
                CREATE TABLE IF NOT EXISTS comparison_features (
                    id TEXT PRIMARY KEY,
                    case_id TEXT NOT NULL,
                    feature TEXT NOT NULL,
                    claim_mapping TEXT NOT NULL,
                    reference_mapping TEXT NOT NULL DEFAULT '{}',
                    sort_order INTEGER NOT NULL DEFAULT 0
                )
            """)
        exec(
            db,
            """
                CREATE TABLE IF NOT EXISTS oa_points (
                    id TEXT PRIMARY KEY,
                    case_id TEXT NOT NULL,
                    objection_type TEXT NOT NULL,
                    examiner_argument TEXT NOT NULL,
                    response_strategy TEXT,
                    response_text TEXT,
                    created_at TEXT NOT NULL
                )
            """)
        exec(
            db,
            """
                CREATE INDEX IF NOT EXISTS idx_claims_case ON claims(case_id, number)
            """)
        exec(
            db,
            """
                CREATE INDEX IF NOT EXISTS idx_oa_case ON oa_points(case_id, created_at DESC)
            """)
    }

    // MARK: - Claims Tree

    /// 保存权利要求树到案件数据库（先删除再插入）
    public func saveClaimsTree(_ tree: ClaimsTree, caseId: String) async throws {
        guard let db = openDB(for: caseId) else { throw dbError(nil) }
        defer { sqlite3_close(db) }
        execParameterized(db, "DELETE FROM claims WHERE case_id=?", caseId)
        let iso = ISO8601DateFormatter().string(from: Date())
        for node in tree.independentClaims + tree.dependentClaims {
            var stmt: OpaquePointer?
            let sql: String = """
                    INSERT INTO claims (id, case_id, number, text, category, parent_number, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { continue }
            bind(db, stmt, 1, node.id.uuidString)
            bind(db, stmt, 2, caseId)
            bind(db, stmt, 3, node.number)
            bind(db, stmt, 4, node.text)
            bind(db, stmt, 5, node.category.rawValue)
            bind(db, stmt, 6, node.parentClaimNumber)
            bind(db, stmt, 7, iso)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// 加载案件的权利要求树
    public func loadClaimsTree(caseId: String) async -> ClaimsTree? {
        guard let db = openDB(for: caseId) else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db,
                "SELECT id, number, text, category, parent_number FROM claims WHERE case_id=? ORDER BY number",
                -1, &stmt, nil) == SQLITE_OK, let stmt
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(db, stmt, 1, caseId)
        var independent: [ClaimNode] = []
        var dependent: [ClaimNode] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = col(db, stmt, 0),
                let num = col(db, stmt, 1),
                let text = col(db, stmt, 2),
                let catRaw = col(db, stmt, 3),

                let uuid: UUID = UUID(uuidString: idStr)
            else { continue }
            let parent = col(db, stmt, 4)
            let category: ClaimCategory = ClaimCategory(rawValue: catRaw) ?? .independent
            let node = ClaimNode(id: uuid, number: num, text: text, category: category, parentClaimNumber: parent)
            if category == .independent { independent.append(node) } else { dependent.append(node) }
        }
        guard !independent.isEmpty || !dependent.isEmpty else { return nil }
        return ClaimsTree(caseId: caseId, independentClaims: independent, dependentClaims: dependent)
    }

    // MARK: - Comparison Matrix

    /// 保存技术特征对比矩阵（先删除再插入）
    public func saveComparisonMatrix(_ matrix: ComparisonMatrix, caseId: String) async throws {
        guard let db = openDB(for: caseId) else { throw dbError(nil) }
        defer { sqlite3_close(db) }
        execParameterized(db, "DELETE FROM comparison_features WHERE case_id=?", caseId)
        for (index, row) in matrix.featureRows.enumerated() {
            let refMapping: String =
                (try? JSONEncoder().encode(row.referenceMapping)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            var stmt: OpaquePointer?
            let sql: String = """
                    INSERT INTO comparison_features (id, case_id, feature, claim_mapping, reference_mapping, sort_order)
                    VALUES (?, ?, ?, ?, ?, ?)
                """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { continue }
            bind(db, stmt, 1, UUID().uuidString)
            bind(db, stmt, 2, caseId)
            bind(db, stmt, 3, row.feature)
            bind(db, stmt, 4, row.claimMapping)
            bind(db, stmt, 5, refMapping)
            bind(db, stmt, 6, String(index))
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// 加载技术特征对比矩阵
    public func loadComparisonMatrix(caseId: String) async -> ComparisonMatrix? {
        guard let db = openDB(for: caseId) else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db,
                // swiftlint:disable:next line_length
                "SELECT feature, claim_mapping, reference_mapping FROM comparison_features WHERE case_id=? ORDER BY sort_order",
                -1, &stmt, nil) == SQLITE_OK, let stmt
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        bind(db, stmt, 1, caseId)
        var rows: [FeatureRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let feature = col(db, stmt, 0),
                let mapping = col(db, stmt, 1)
            else { continue }
            let refMapping: [String: String] = {
                guard let json = col(db, stmt, 2),
                    let data = json.data(using: .utf8)
                else { return [:] }
                return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            }()
            rows.append(FeatureRow(feature: feature, claimMapping: mapping, referenceMapping: refMapping))
        }
        guard !rows.isEmpty else { return nil }
        return ComparisonMatrix(
            caseId: caseId, featureRows: rows, references: Array(Set(rows.flatMap { $0.referenceMapping.keys })))
    }

    // MARK: - OA Points

    /// 保存一条审查意见
    public func saveOAPoint(_ point: OAPoint, caseId: String) async throws {
        guard let db = openDB(for: caseId) else { throw dbError(nil) }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql: String =
            "INSERT INTO oa_points (id, case_id, objection_type, examiner_argument, "
            + "response_strategy, response_text, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw dbError(db)
        }
        bind(db, stmt, 1, point.id.uuidString)
        bind(db, stmt, 2, caseId)
        bind(db, stmt, 3, point.objectionType.rawValue)
        bind(db, stmt, 4, point.examinerArgument)
        bind(db, stmt, 5, point.responseStrategy)
        bind(db, stmt, 6, point.responseText)
        bind(db, stmt, 7, ISO8601DateFormatter().string(from: point.createdAt))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError(db) }
        sqlite3_finalize(stmt)
    }

    /// 加载案件的所有审查意见
    public func loadOAPoints(caseId: String) async -> [OAPoint] {
        guard let db = openDB(for: caseId) else { return [] }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db,
                "SELECT id, objection_type, examiner_argument, response_strategy, response_text, created_at FROM oa_points WHERE case_id=? ORDER BY created_at DESC",  // swiftlint:disable:this line_length
                -1, &stmt, nil) == SQLITE_OK, let stmt
        else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(db, stmt, 1, caseId)
        var points: [OAPoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = col(db, stmt, 0),
                let typeRaw = col(db, stmt, 1),
                let arg = col(db, stmt, 2),
                let uuid: UUID = UUID(uuidString: idStr),
                let type = OAObjectionType(rawValue: typeRaw)
            else { continue }
            let created: Date = col(db, stmt, 5).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
            points.append(
                OAPoint(
                    id: uuid,
                    objectionType: type,
                    examinerArgument: arg,
                    responseStrategy: col(db, stmt, 3),
                    responseText: col(db, stmt, 4),
                    createdAt: created
                ))
        }
        return points
    }

    // MARK: - Helpers

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func exec(_ db: OpaquePointer?, _ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func bind(_ db: OpaquePointer?, _ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let val = value {
            sqlite3_bind_text(stmt, index, (val as NSString).utf8String, -1, Self.SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func col(_ db: OpaquePointer?, _ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cstr)
    }

    private func isSafeCaseId(_ caseId: String) -> Bool {
        !caseId.isEmpty && caseId.count <= 128
            && caseId.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private func execParameterized(_ db: OpaquePointer?, _ sql: String, _ value: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (value as NSString).utf8String, -1, Self.SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    private func dbError(_ db: OpaquePointer?) -> Error {
        let msg: String = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
        return NSError(
            domain: "YunPatCore.CaseDatabase", code: Int(sqlite3_errcode(db)),
            userInfo: [NSLocalizedDescriptionKey: msg])
    }
}

// MARK: - Claims Tree

/// 权利要求树 — 包含独立权利要求和从属权利要求
public struct ClaimsTree: Sendable, Codable {
    public let caseId: String
    public var independentClaims: [ClaimNode]
    public var dependentClaims: [ClaimNode]
    public init(caseId: String, independentClaims: [ClaimNode] = [], dependentClaims: [ClaimNode] = []) {
        self.caseId = caseId
        self.independentClaims = independentClaims
        self.dependentClaims = dependentClaims
    }
}

/// 权利要求节点
public struct ClaimNode: Sendable, Codable, Identifiable {
    public let id: UUID
    public let number: String
    public let text: String
    public let category: ClaimCategory
    public var parentClaimNumber: String?
    public init(
        id: UUID = UUID(), number: String, text: String, category: ClaimCategory, parentClaimNumber: String? = nil
    ) {
        self.id = id
        self.number = number
        self.text = text
        self.category = category
        self.parentClaimNumber = parentClaimNumber
    }
}

/// 权利要求类别
public enum ClaimCategory: String, Sendable, Codable {
    case independent
    case dependent
    case multipleDependent
}

// MARK: - Comparison Matrix

/// 技术特征对比矩阵 — 将权利要求特征映射到对比文件
public struct ComparisonMatrix: Sendable, Codable {
    public let caseId: String
    public let featureRows: [FeatureRow]
    public let references: [String]
    public init(caseId: String, featureRows: [FeatureRow] = [], references: [String] = []) {
        self.caseId = caseId
        self.featureRows = featureRows
        self.references = references
    }
}

/// 对比矩阵的一行 — 单个技术特征及其在权利要求和对比文件中的映射
public struct FeatureRow: Sendable, Codable {
    public let feature: String
    public let claimMapping: String
    public let referenceMapping: [String: String]
    public init(feature: String, claimMapping: String, referenceMapping: [String: String] = [:]) {
        self.feature = feature
        self.claimMapping = claimMapping
        self.referenceMapping = referenceMapping
    }
}

// MARK: - OA Points

/// 审查意见（OA）逐条 — 审查员论点及代理人答复策略
public struct OAPoint: Sendable, Codable, Identifiable {
    public let id: UUID
    public let objectionType: OAObjectionType
    public let examinerArgument: String
    public var responseStrategy: String?
    public var responseText: String?
    public let createdAt: Date
    public init(
        id: UUID = UUID(), objectionType: OAObjectionType, examinerArgument: String,
        responseStrategy: String? = nil, responseText: String? = nil, createdAt: Date = Date()
    ) {
        self.id = id
        self.objectionType = objectionType
        self.examinerArgument = examinerArgument
        self.responseStrategy = responseStrategy
        self.responseText = responseText
        self.createdAt = createdAt
    }
}

/// 审查意见反对类型
public enum OAObjectionType: String, Sendable, Codable {
    case novelty
    case inventiveStep
    case clarity
    case support
    case unity
    case amendment
    case formal
    case other
}
