import Foundation

// MARK: - CaseWorkspaceStore

/// 持久化案件工作区元数据（UserDefaults + JSON）
public actor CaseWorkspaceStore {
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let keyPrefix: String = "yunpat.workspace."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - CRUD

    public func save(_ workspace: CaseWorkspace) throws {
        let data = try encoder.encode(workspace)
        defaults.set(data, forKey: keyPrefix + workspace.id.uuidString)
    }

    public func load(id: UUID) -> CaseWorkspace? {
        guard let data = defaults.data(forKey: keyPrefix + id.uuidString) else { return nil }
        return try? decoder.decode(CaseWorkspace.self, from: data)
    }

    public func loadByCaseId(_ caseId: String) -> CaseWorkspace? {
        listAll().first { $0.caseId == caseId }
    }

    public func listAll() -> [CaseWorkspace] {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(keyPrefix) }
            .compactMap { key in
                guard let data = defaults.data(forKey: key) else { return nil }
                return try? decoder.decode(CaseWorkspace.self, from: data)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func remove(id: UUID) {
        defaults.removeObject(forKey: keyPrefix + id.uuidString)
    }

    public func removeByCaseId(_ caseId: String) {
        listAll()
            .filter { $0.caseId == caseId }
            .forEach { remove(id: $0.id) }
    }
}
