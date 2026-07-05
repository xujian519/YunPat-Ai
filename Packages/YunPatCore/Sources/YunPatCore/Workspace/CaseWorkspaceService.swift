import Foundation

// MARK: - CaseWorkspaceService

/// 案件工作区业务服务：封装创建、查询、更新与默认路径生成。
public actor CaseWorkspaceService {
    private let store: CaseWorkspaceStore

    public init(store: CaseWorkspaceStore = CaseWorkspaceStore()) {
        self.store = store
    }

    // MARK: - Read

    public func workspace(id: UUID) async -> CaseWorkspace? {
        await store.load(id: id)
    }

    public func workspace(forCaseId caseId: String) async -> CaseWorkspace? {
        await store.loadByCaseId(caseId)
    }

    public func listAll() async -> [CaseWorkspace] {
        await store.listAll()
    }

    public func list(forCaseIds caseIds: [String]) async -> [CaseWorkspace] {
        await store.listAll().filter { caseIds.contains($0.caseId) }
    }

    // MARK: - Write

    /// 创建新工作区。若未提供路径，则生成默认路径 `~/YunPat/workspaces/<caseId>`。
    @discardableResult
    public func createWorkspace(
        title: String,
        caseId: String,
        path: String? = nil
    ) async throws -> CaseWorkspace {
        if let existing = await store.loadByCaseId(caseId) {
            return existing
        }

        let workspacePath = path ?? defaultWorkspacePath(for: caseId)
        let workspace = CaseWorkspace(
            caseId: caseId,
            title: title,
            workspacePath: workspacePath
        )
        try await store.save(workspace)
        return workspace
    }

    public func updateWorkspace(_ workspace: CaseWorkspace) async throws {
        var mutable = workspace
        mutable.modifiedAt = Date()
        try await store.save(mutable)
    }

    public func updateStatus(id: UUID, status: CaseWorkspaceStatus) async throws {
        guard var workspace = await store.load(id: id) else {
            throw CaseWorkspaceError.workspaceNotFound(id.uuidString)
        }
        workspace.status = status
        try await updateWorkspace(workspace)
    }

    public func updateNotes(id: UUID, notes: String) async throws {
        guard var workspace = await store.load(id: id) else {
            throw CaseWorkspaceError.workspaceNotFound(id.uuidString)
        }
        workspace.notes = notes
        try await updateWorkspace(workspace)
    }

    public func updatePath(id: UUID, path: String?) async throws {
        guard var workspace = await store.load(id: id) else {
            throw CaseWorkspaceError.workspaceNotFound(id.uuidString)
        }
        workspace.workspacePath = path
        try await updateWorkspace(workspace)
    }

    public func removeWorkspace(id: UUID) async throws {
        await store.remove(id: id)
    }

    // MARK: - Ensure

    /// 保证指定 caseId 存在工作区；不存在则创建。
    @discardableResult
    public func ensureWorkspace(
        forCaseId caseId: String,
        title: String
    ) async throws -> CaseWorkspace {
        if let existing = await store.loadByCaseId(caseId) {
            return existing
        }
        return try await createWorkspace(title: title, caseId: caseId)
    }

    // MARK: - Helpers

    private func defaultWorkspacePath(for caseId: String) -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("YunPat/workspaces/\(caseId)")
            .path
    }
}

// MARK: - Errors

public enum CaseWorkspaceError: Error, Sendable {
    case workspaceNotFound(String)
}
