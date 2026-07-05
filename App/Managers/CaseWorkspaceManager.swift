import Foundation
import SwiftUI
import YunPatCore

@MainActor
final class CaseWorkspaceManager: ObservableObject {
    @Published var workspaces: [CaseWorkspace] = []
    @Published var selectedWorkspace: CaseWorkspace?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    var selectedCaseId: String? {
        didSet { Task { await load() } }
    }

    private let service: CaseWorkspaceService

    init(service: CaseWorkspaceService = CaseWorkspaceService()) {
        self.service = service
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        workspaces = await service.listAll()
        if let caseId = selectedCaseId {
            selectedWorkspace = await service.workspace(forCaseId: caseId)
        } else {
            selectedWorkspace = nil
        }
        isLoading = false
    }

    func createWorkspace(title: String, caseId: String, path: String? = nil) async {
        do {
            let workspace = try await service.createWorkspace(title: title, caseId: caseId, path: path)
            selectedWorkspace = workspace
            await load()
        } catch {
            errorMessage = "创建工作区失败: \(error.localizedDescription)"
        }
    }

    func ensureWorkspace(title: String, caseId: String) async {
        do {
            let workspace = try await service.ensureWorkspace(forCaseId: caseId, title: title)
            selectedWorkspace = workspace
            await load()
        } catch {
            errorMessage = "初始化工作区失败: \(error.localizedDescription)"
        }
    }

    func updateStatus(_ status: CaseWorkspaceStatus) async {
        guard let workspace = selectedWorkspace else { return }
        do {
            try await service.updateStatus(id: workspace.id, status: status)
            await load()
        } catch {
            errorMessage = "更新状态失败: \(error.localizedDescription)"
        }
    }

    func updateNotes(_ notes: String) async {
        guard let workspace = selectedWorkspace else { return }
        do {
            try await service.updateNotes(id: workspace.id, notes: notes)
            await load()
        } catch {
            errorMessage = "更新备注失败: \(error.localizedDescription)"
        }
    }

    func updateTags(_ tags: [String]) async {
        guard var workspace = selectedWorkspace else { return }
        workspace.tags = tags
        do {
            try await service.updateWorkspace(workspace)
            await load()
        } catch {
            errorMessage = "更新标签失败: \(error.localizedDescription)"
        }
    }

    func updatePath(_ path: String?) async {
        guard let workspace = selectedWorkspace else { return }
        do {
            try await service.updatePath(id: workspace.id, path: path)
            await load()
        } catch {
            errorMessage = "更新路径失败: \(error.localizedDescription)"
        }
    }

    func removeSelectedWorkspace() async {
        guard let workspace = selectedWorkspace else { return }
        do {
            try await service.removeWorkspace(id: workspace.id)
            selectedWorkspace = nil
            await load()
        } catch {
            errorMessage = "删除工作区失败: \(error.localizedDescription)"
        }
    }
}
