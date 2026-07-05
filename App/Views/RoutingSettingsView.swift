import SwiftUI
import YunPatCore

struct RoutingSettingsView: View {
    @State private var config: TokenBudgetConfig = .default
    @State private var defaultStrategy: RoutingStrategy = .balanced
    @State private var saved: Bool = false

    private let budgetService: TokenBudgetService = TokenBudgetService()

    var body: some View {
        Form {
            Section("路由策略") {
                Picker("默认策略", selection: $defaultStrategy) {
                    Text("平衡").tag(RoutingStrategy.balanced)
                    Text("经济").tag(RoutingStrategy.cheap)
                    Text("能力优先").tag(RoutingStrategy.capable)
                    Text("仅本地模型").tag(RoutingStrategy.localOnly)
                }
                .pickerStyle(.radioGroup)
            }

            Section("Token 预算") {
                HStack {
                    Text("全局月度 Token")
                    Spacer()
                    TextField("", value: $config.globalMonthlyTokens, format: .number)
                        .frame(width: 120)
                }
                HStack {
                    Text("案件级 Token")
                    Spacer()
                    TextField("", value: $config.perCaseTokens, format: .number)
                        .frame(width: 120)
                }

                Divider()

                HStack {
                    Text("全局月度 USD")
                    Spacer()
                    TextField("", value: $config.globalMonthlyUsd, format: .number)
                        .frame(width: 120)
                }
                HStack {
                    Text("案件级 USD")
                    Spacer()
                    TextField("", value: $config.perCaseUsd, format: .number)
                        .frame(width: 120)
                }

                Text("设为 0 表示不限制")
                    .font(FontStyle.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("重置为默认值") {
                    config = .default
                    defaultStrategy = .balanced
                }
                Button("保存") {
                    saved = true
                }
                .buttonStyle(.borderedProminent)
            }

            if saved {
                Text("已保存（当前会话生效）")
                    .font(FontStyle.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .frame(width: PanelWidth.settingsWidth, height: PanelWidth.settingsHeight)
    }
}
