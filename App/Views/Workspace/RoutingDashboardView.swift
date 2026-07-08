import SwiftUI
import YunPatCore

/// PilotDeck 风格路由策略 Dashboard
struct RoutingDashboardView: View {
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared
    @StateObject private var manager = RoutingDashboardManager()

    @AppStorage("yunpat.routing.selectedModel") private var selectedModel: String = "auto"
    @AppStorage("yunpat.routing.autoFallback") private var autoFallback: Bool = true
    @AppStorage("yunpat.routing.preferClaudeLongText") private var preferClaudeLongText: Bool = true
    @AppStorage("yunpat.routing.preferDeepSeekCode") private var preferDeepSeekCode: Bool = false

    private enum AggregationScope: String, CaseIterable {
        case project = "项目"
        case total = "总计"
    }

    @State private var aggregation: AggregationScope = .project

    private let models: [String] = ["auto", "gpt-4o", "claude-sonnet", "deepseek-chat", "glm-4"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                PageHeader(
                    title: "路由",
                    subtitle: "模型路由策略与实时成本监控",
                    actions: {
                        HStack(spacing: Spacing.xxs) {
                            Picker("", selection: $aggregation) {
                                ForEach(AggregationScope.allCases, id: \.self) { scope in
                                    Text(scope.rawValue).tag(scope)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)

                            Button(
                                action: { Task { await manager.load() } },
                                label: {
                                    HStack(spacing: Spacing.xxs) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: IconSize.inlineSmall))
                                        Text("刷新")
                                            .font(FontStyle.callout)
                                    }
                                }
                            )
                            .buttonStyle(.plain)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.appSurfacePrimary)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .stroke(Color.appSeparator.opacity(0.5), lineWidth: BorderWidth.hairline)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                        }
                    }
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: Spacing.md) {
                    StatCard(
                        title: "当前模型",
                        value: manager.activeProvider,
                        icon: "cpu",
                        trend: selectedModel == "auto" ? "自动路由" : "手动指定",
                        color: .blue
                    )
                    StatCard(
                        title: "今日 Token",
                        value: manager.todayTokensFormatted,
                        icon: "text.alignleft",
                        trend: aggregation == .total ? "累计" : "今日",
                        color: .orange
                    )
                    StatCard(
                        title: "累计成本",
                        value: manager.totalCostFormatted,
                        icon: "dollarsign.circle",
                        trend: manager.snapshot.map { "\(Int($0.percentTokens))% 预算" } ?? "—",
                        color: .green
                    )
                    StatCard(
                        title: "提供商数",
                        value: "\(manager.providerStats.filter { $0.tokenCount > 0 }.count)",
                        icon: "server.rack",
                        trend: "活跃",
                        color: .purple
                    )
                }

                strategySection
                providerSection
            }
            .padding(Spacing.lg)
        }
        .background(Color.appBackground)
        .task { await manager.load() }
    }

    private var strategySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("路由策略")

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Picker("默认模型", selection: $selectedModel) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("自动降级", isOn: $autoFallback)
                Toggle("长文本优先 Claude", isOn: $preferClaudeLongText)
                Toggle("代码任务优先 DeepSeek", isOn: $preferDeepSeekCode)
            }
            .padding()
            .appCard()
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("提供商状态")

            if manager.providerStats.isEmpty {
                Text("暂无使用记录")
                    .font(FontStyle.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(manager.providerStats) { stat in
                            ProviderStatusCard(
                                name: stat.name,
                                status: stat.isHealthy ? .healthy : .offline,
                                tokenCount: stat.tokenCount
                            )
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(FontStyle.callout)
            .fontWeight(.semibold)
            .foregroundStyle(Color.appTextSecondary)
    }
}

enum ProviderHealth {
    case healthy, degraded, offline
}

struct ProviderStatusCard: View {
    let name: String
    let status: ProviderHealth
    var tokenCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(FontStyle.callout)
                Spacer()
            }
            if tokenCount > 0 {
                let formatted: String = tokenCount >= 1000
                    ? String(format: "%.1fK", Double(tokenCount) / 1000)
                    : "\(tokenCount)"
                Text("\(formatted) tokens")
                    .font(FontStyle.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 120)
        .appCard()
    }

    private var color: Color {
        switch status {
        case .healthy: return Color.statusSuccess
        case .degraded: return Color.statusWarning
        case .offline: return Color.statusDestructive
        }
    }
}

#Preview {
    RoutingDashboardView()
        .frame(width: 900, height: 600)
}
