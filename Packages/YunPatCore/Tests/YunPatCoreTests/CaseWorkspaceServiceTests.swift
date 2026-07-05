import Foundation
import Testing
@testable import YunPatCore

struct CaseWorkspaceServiceTests {
    private let store: CaseWorkspaceStore = CaseWorkspaceStore(defaults: .standard)
    private let service: CaseWorkspaceService = CaseWorkspaceService(
        store: CaseWorkspaceStore(defaults: .standard)
    )

    init() async {
        await cleanup()
    }

    private func cleanup() async {
        let all = await store.listAll()
        for workspace in all {
            await store.remove(id: workspace.id)
        }
    }

    @Test
    func test_createWorkspace_persistsAndReturnsWorkspace() async throws {
        let workspace = try await service.createWorkspace(title: "测试案件", caseId: "WS-001")

        #expect(workspace.caseId == "WS-001")
        #expect(workspace.title == "测试案件")
        #expect(workspace.status == .active)

        let loaded = await service.workspace(forCaseId: "WS-001")
        #expect(loaded?.id == workspace.id)
    }

    @Test
    func test_createWorkspace_doesNotDuplicateExistingCaseId() async throws {
        let first = try await service.createWorkspace(title: "First", caseId: "WS-002")
        let second = try await service.createWorkspace(title: "Second", caseId: "WS-002")

        #expect(first.id == second.id)
        #expect(second.title == "First")
    }

    @Test
    func test_updateStatus() async throws {
        let workspace = try await service.createWorkspace(title: "Status", caseId: "WS-003")
        try await service.updateStatus(id: workspace.id, status: .onHold)

        let loaded = await service.workspace(forCaseId: "WS-003")
        #expect(loaded?.status == .onHold)
    }

    @Test
    func test_updateNotesAndPath() async throws {
        let workspace = try await service.createWorkspace(title: "Notes", caseId: "WS-004")
        try await service.updateNotes(id: workspace.id, notes: "关键备注")
        try await service.updatePath(id: workspace.id, path: "/tmp/yunpat/ws-004")

        let loaded = await service.workspace(forCaseId: "WS-004")
        #expect(loaded?.notes == "关键备注")
        #expect(loaded?.workspacePath == "/tmp/yunpat/ws-004")
    }

    @Test
    func test_removeWorkspace() async throws {
        let workspace = try await service.createWorkspace(title: "Remove", caseId: "WS-005")
        try await service.removeWorkspace(id: workspace.id)

        let loaded = await service.workspace(forCaseId: "WS-005")
        #expect(loaded == nil)
    }
}
