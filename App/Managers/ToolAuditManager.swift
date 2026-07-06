import Foundation
import SwiftUI
import YunPatCore

@MainActor
final class ToolAuditManager: ObservableObject {
    @Published var entries: [ToolAuditRecorder.AuditEntry] = []
    @Published var selectedEntry: ToolAuditRecorder.AuditEntry?
    @Published var searchText: String = ""
    @Published var summary: ToolAuditRecorder.AuditSummary?
    @Published var isLoading: Bool = false

    private let recorder: ToolAuditRecorder

    init(recorder: ToolAuditRecorder = .shared) {
        self.recorder = recorder
    }

    func load() async {
        isLoading = true
        let all: [ToolAuditRecorder.AuditEntry] = await recorder.recent(limit: 200)
        entries = all
        summary = await recorder.summary()
        isLoading = false
    }

    func search() async {
        isLoading = true
        let results: [ToolAuditRecorder.AuditEntry] = await recorder.search(
            toolName: searchText.isEmpty ? nil : searchText,
            limit: 200
        )
        entries = results
        isLoading = false
    }

    func select(_ entry: ToolAuditRecorder.AuditEntry) {
        selectedEntry = entry
    }

    func clear() async {
        await recorder.clear()
        await load()
    }

    func exportJSON() async -> Data? {
        await recorder.export()
    }

    var filteredEntries: [ToolAuditRecorder.AuditEntry] {
        if searchText.isEmpty { return entries }
        return entries.filter { entry in
            entry.toolName.localizedCaseInsensitiveContains(searchText)
                || entry.resultSummary.localizedCaseInsensitiveContains(searchText)
        }
    }
}
