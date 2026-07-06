import SwiftUI
import YunPatCore

/// 路由策略卡片式 Dashboard
struct RoutingDashboardView: View {
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared
    @State private var selectedModel: String = "auto"

    private let models: [String] = ["auto", "gpt-4o", "claude-sonnet", "deepseek-chat", "glm-4"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

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

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("路由")
                .font(FontStyle.largeTitle)
            Text("模型路由策略与实时成本监控")
                .font(FontStyle.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var strategySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("路由策略")
                .font(FontStyle.title2)

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
            .background(Color.appSurfacePrimary)
            .cornerRadius(CornerRadius.lg)
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("提供商状态")
                .font(FontStyle.title2)

            HStack(spacing: Spacing.md) {
                ProviderStatusCard(name: "OpenAI", status: .healthy)
                ProviderStatusCard(name: "Anthropic", status: .healthy)
                ProviderStatusCard(name: "DeepSeek", status: .degraded)
                ProviderStatusCard(name: "GLM", status: .healthy)
            }
        }
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
        .background(Color.appSurfacePrimary)
        .cornerRadius(CornerRadius.lg)
    }

    private var color: Color {
        switch status {
        case .healthy: return .green
        case .degraded: return .orange
        case .offline: return .red
        }
    }
}

#Preview {
    RoutingDashboardView()
        .frame(width: 900, height: 600)
}
