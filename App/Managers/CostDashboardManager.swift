import Foundation
import SwiftUI
import YunPatCore

@MainActor
final class CostDashboardManager: ObservableObject {
    @Published var snapshot: TokenBudgetSnapshot?
    @Published var recentRecords: [TokenUsageRecord] = []
    @Published var isLoading: Bool = false

    private let routingEngine: RoutingEngine
    private let usageStore: TokenUsageStore

    init(routingEngine: RoutingEngine = .shared,
         usageStore: TokenUsageStore = TokenUsageStore()) {
        self.routingEngine = routingEngine
        self.usageStore = usageStore
    }

    func load(caseId: String?) async {
        isLoading = true
        snapshot = await routingEngine.snapshot(caseId: caseId)
        if let caseId {
            recentRecords = (try? await usageStore.loadForCase(caseId: caseId)) ?? []
        } else {
            recentRecords = (try? await usageStore.loadAll()) ?? []
        }
        recentRecords = Array(recentRecords.sorted { $0.timestamp > $1.timestamp }.prefix(20))
        isLoading = false
    }

    func resetCase(caseId: String) async {
        await routingEngine.resetCaseBudget(caseId: caseId)
        await load(caseId: caseId)
    }

    func resetGlobal() async {
        await routingEngine.resetGlobalBudget()
        await load(caseId: nil)
    }
}
