import Foundation
import SwiftUI
import YunPatCore

@MainActor
final class MemoryDashboardManager: ObservableObject {
    @Published var layerCounts: [MemoryLayer: Int] = [:]
    @Published var recentEntries: [MemoryEntryMetadata] = []
    @Published var filteredEntries: [MemoryEntryMetadata] = []
    @Published var selectedLayer: MemoryLayer = .caseContext
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let llmStore: LLMMemoryStore
    private let memoryStore: MemoryStore

    init(
        llmStore: LLMMemoryStore = .shared,
        memoryStore: MemoryStore = MemoryStore()
    ) {
        self.llmStore = llmStore
        self.memoryStore = memoryStore
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        let caseIds: [String] = await memoryStore.listCaseIds()

        let ltm: LongTermMemory = await memoryStore.loadLongTermMemory()
        let ltmCount: Int = ltm.legalPrecedents.count
            + ltm.successfulStrategies.count
            + ltm.learnedPitfalls.count
            + ltm.items.count

        let global: GlobalMemory = await memoryStore.loadGlobalMemory()
        let globalCount: Int = global.terminologyPreferences.count
            + global.preferredProviders.count
            + (global.writingStyleEntry != nil ? 1 : 0)

        let allEntries = llmStore.listAll()

        layerCounts = [
            .working: 0,
            .session: 0,
            .caseContext: caseIds.count,
            .longTerm: ltmCount,
            .global: globalCount
        ]

        recentEntries = allEntries.sorted { $0.id < $1.id }
        updateFilter()
        isLoading = false
    }

    func selectLayer(_ layer: MemoryLayer) {
        selectedLayer = layer
        updateFilter()
    }

    private func updateFilter() {
        switch selectedLayer {
        case .longTerm:
            filteredEntries = recentEntries.filter { $0.type == .feedback || $0.type == .reference }
        case .global:
            filteredEntries = recentEntries.filter { $0.type == .user }
        case .caseContext:
            filteredEntries = recentEntries.filter { $0.type == .project }
        default:
            filteredEntries = Array(recentEntries.prefix(10))
        }
    }
}
