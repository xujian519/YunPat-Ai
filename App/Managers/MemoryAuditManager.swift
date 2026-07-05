import Foundation
import SwiftUI
import YunPatCore

@MainActor
final class MemoryAuditManager: ObservableObject {
    @Published var entries: [AuditableMemoryEntry] = []
    @Published var selectedEntry: AuditableMemoryEntry?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    var selectedCaseId: String? {
        didSet { Task { await load() } }
    }

    private let service: MemoryAuditService

    init(service: MemoryAuditService = MemoryAuditService()) {
        self.service = service
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            entries = await service.listEntries(caseId: selectedCaseId)
            if let selected = selectedEntry, !entries.contains(where: { $0.id == selected.id }) {
                selectedEntry = nil
            }
        }
        isLoading = false
    }

    func select(_ entry: AuditableMemoryEntry) {
        selectedEntry = entry
    }

    func update(content: String) async {
        guard var entry = selectedEntry else { return }
        entry.content = content
        do {
            try await service.updateEntry(entry, caseId: selectedCaseId)
            await load()
        } catch {
            errorMessage = "更新失败: \(error.localizedDescription)"
        }
    }

    func togglePin(_ entry: AuditableMemoryEntry) async {
        do {
            try await service.togglePin(entry, caseId: selectedCaseId)
            await load()
        } catch {
            errorMessage = "Pin 操作失败: \(error.localizedDescription)"
        }
    }

    func delete(_ entry: AuditableMemoryEntry) async {
        do {
            try await service.deleteEntry(entry, caseId: selectedCaseId)
            if selectedEntry?.id == entry.id { selectedEntry = nil }
            await load()
        } catch {
            errorMessage = "删除失败: \(error.localizedDescription)"
        }
    }

    func rollback(_ entry: AuditableMemoryEntry) async {
        do {
            _ = try await service.rollbackEntry(entry, caseId: selectedCaseId)
            await load()
        } catch {
            errorMessage = "回滚失败: \(error.localizedDescription)"
        }
    }
}
