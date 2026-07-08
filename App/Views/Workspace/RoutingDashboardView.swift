import SwiftUI
import YunPatCore

/// PilotDeck 风格路由策略 Dashboard
struct RoutingDashboardView: View {
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared
    @State private var selectedModel: String = "auto"
    @State private var aggregation: AggregationScope = .project

    private enum AggregationScope: String, CaseIterable {
        case project = "项目"
        case total = "总计"
    }

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
                                action: {},
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
                        value: selectedModel.uppercased(),
                        icon: "cpu",
                        trend: "自动路由",
                        color: .blue
                    )
                    StatCard(
                        title: "平均延迟",
                        value: "1.2s",
                        icon: "clock",
                        trend: "较昨日 -12%",
                        color: .green
                    )
                    StatCard(
                        title: "今日 Token",
                        value: "42K",
                        icon: "text.alignleft",
                        trend: "较昨日 +8%",
                        color: .orange
                    )
                    StatCard(
                        title: "失败率",
                        value: "0.3%",
                        icon: "exclamationmark.triangle",
                        trend: "稳定",
                        color: .red
                    )
                }

                strategySection
                providerSection
            }
            .padding(Spacing.lg)
        }
        .background(Color.appBackground)
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

                Toggle("自动降级", isOn: .constant(true))
                Toggle("长文本优先 Claude", isOn: .constant(true))
                Toggle("代码任务优先 DeepSeek", isOn: .constant(false))
            }
            .padding()
            .appCard()
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("提供商状态")

            HStack(spacing: Spacing.md) {
                ProviderStatusCard(name: "OpenAI", status: .healthy)
                ProviderStatusCard(name: "Anthropic", status: .healthy)
                ProviderStatusCard(name: "DeepSeek", status: .degraded)
                ProviderStatusCard(name: "GLM", status: .healthy)
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

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(name)
                .font(FontStyle.callout)
            Spacer()
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
