import Foundation
import os

/// 跨案件引用类型 — 设计 §6: 优先权链 + 对比文件链
public enum CaseRelationType: String, Sendable, Codable {
    case priority       // 优先权
    case divisional     // 分案
    case reference      // 对比文件 (citation)
    case family         // 同族
    case continuation   // 接续案
}

/// 跨案件引用关系 — 描述两个案件之间的法律关联
public struct CaseRelation: Sendable, Codable, Identifiable {
    public let id: UUID
    public let fromCaseId: String
    public let toCaseId: String
    public let toCaseTitle: String
    public let relationType: CaseRelationType
    public let applicationNumber: String?
    public let note: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        fromCaseId: String,
        toCaseId: String,
        toCaseTitle: String,
        relationType: CaseRelationType,
        applicationNumber: String? = nil,
        note: String = ""
    ) {
        self.id = id
        self.fromCaseId = fromCaseId
        self.toCaseId = toCaseId
        self.toCaseTitle = toCaseTitle
        self.relationType = relationType
        self.applicationNumber = applicationNumber
        self.note = note
        self.createdAt = Date()
    }
}

/// 跨案件引用存储 — 基于 UserDefaults 持久化案件间的关系图谱
///
/// 支持正向查询（本案的优先权/分案/对比文件）和反向查询（某对比文件在哪些案件中用过）
public actor CaseRelationStore {
    public static let shared = CaseRelationStore()
    private let logger = Logger(subsystem: "com.yunpat", category: "CaseRelationStore")
    private let defaults: UserDefaults
    private let key: String = "yunpat.case.relations"
    private let encoder: JSONEncoder = JSONEncoder()
    private let decoder: JSONDecoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 添加案件间引用关系
    public func addRelation(_ relation: CaseRelation) throws {
        var relations = loadAll()
        relations.removeAll {
            $0.fromCaseId == relation.fromCaseId
            && $0.toCaseId == relation.toCaseId
            && $0.relationType == relation.relationType
        }
        relations.append(relation)
        try save(relations)
    }

    /// 获取某案件的所有关联案件（正向）
    public func relations(for caseId: String) -> [CaseRelation] {
        loadAll().filter { $0.fromCaseId == caseId }
    }

    /// 反向查询：某对比文件/案件在哪些案件中被引用
    public func reverseLookup(_ targetCaseId: String) -> [CaseRelation] {
        loadAll().filter { $0.toCaseId == targetCaseId }
    }

    /// 按关系类型筛选
    public func relations(for caseId: String, type: CaseRelationType) -> [CaseRelation] {
        loadAll().filter { $0.fromCaseId == caseId && $0.relationType == type }
    }

    /// 获取优先权链
    public func priorityChain(for caseId: String) -> [CaseRelation] {
        var chain: [CaseRelation] = []
        var current: String = caseId
        var visited: Set<String> = [caseId]
        while true {
            let priorities = relations(for: current, type: .priority)
            guard let next = priorities.first,
                  !visited.contains(next.toCaseId) else { break }
            chain.append(next)
            visited.insert(next.toCaseId)
            current = next.toCaseId
        }
        return chain
    }

    /// 移除指定关系
    public func removeRelation(id: UUID) throws {
        var relations = loadAll()
        relations.removeAll { $0.id == id }
        try save(relations)
    }

    // MARK: - Private

    private func loadAll() -> [CaseRelation] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try decoder.decode([CaseRelation].self, from: data)
        } catch {
            logger.error("Failed to decode relations: \(error, privacy: .public)")
            return []
        }
    }

    private func save(_ relations: [CaseRelation]) throws {
        let data = try encoder.encode(relations)
        defaults.set(data, forKey: key)
    }
}
