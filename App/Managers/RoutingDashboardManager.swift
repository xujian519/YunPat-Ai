import Foundation
import SwiftUI
import YunPatCore

@MainActor
final class RoutingDashboardManager: ObservableObject {
    @Published var snapshot: TokenBudgetSnapshot?
    @Published var recentRecords: [TokenUsageRecord] = []
    @Published var todayTokens: Int = 0
    @Published var totalCostUsd: Double = 0
    @Published var activeProvider: String = "AUTO"
    @Published var providerUsage: [String: Int] = [:]
    @Published var isLoading: Bool = false

    private let routingEngine: RoutingEngine
    private let usageStore: TokenUsageStore

    init(
        routingEngine: RoutingEngine = .shared,
        usageStore: TokenUsageStore = TokenUsageStore()
    ) {
        self.routingEngine = routingEngine
        self.usageStore = usageStore
    }

    func load() async {
        isLoading = true

        snapshot = await routingEngine.snapshot()

        let allRecords: [TokenUsageRecord] = (try? await usageStore.loadAll()) ?? []
        let sorted: [TokenUsageRecord] = allRecords.sorted { $0.timestamp > $1.timestamp }

        let calendar: Calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        todayTokens = allRecords
            .filter { $0.timestamp >= startOfToday }
            .reduce(0) { $0 + $1.totalTokens }

        totalCostUsd = allRecords.reduce(0) { $0 + $1.costUsd }

        activeProvider = sorted.first?.provider.uppercased() ?? "AUTO"

        var usage: [String: Int] = [:]
        for record in allRecords {
            usage[record.provider, default: 0] += record.totalTokens
        }
        providerUsage = usage

        recentRecords = Array(sorted.prefix(20))

        isLoading = false
    }

    var todayTokensFormatted: String {
        if todayTokens >= 1_000_000 {
            return String(format: "%.1fM", Double(todayTokens) / 1_000_000)
        } else if todayTokens >= 1_000 {
            return String(format: "%.1fK", Double(todayTokens) / 1_000)
        }
        return "\(todayTokens)"
    }

    var totalCostFormatted: String {
        String(format: "$%.2f", totalCostUsd)
    }

    struct ProviderStat: Identifiable {
        var id: String { name }
        let name: String
        let tokenCount: Int
        let isHealthy: Bool
    }

    var providerStats: [ProviderStat] {
        let knownProviders: [String] = ["openai", "anthropic", "deepseek", "glm"]
        var result: [ProviderStat] = []
        for provider in knownProviders {
            let tokens: Int = providerUsage[provider] ?? 0
            result.append(ProviderStat(
                name: provider.capitalized,
                tokenCount: tokens,
                isHealthy: tokens > 0
            ))
        }
        let extras = providerUsage.keys.filter { !knownProviders.contains($0) }
        for provider in extras {
            result.append(ProviderStat(
                name: provider.capitalized,
                tokenCount: providerUsage[provider] ?? 0,
                isHealthy: true
            ))
        }
        return result.sorted { $0.tokenCount > $1.tokenCount }
    }

    var averageLatencyFormatted: String {
        guard !recentRecords.isEmpty else { return "--" }
        return "--"
    }
}
