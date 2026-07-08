import SwiftUI
import YunPatCore
import YunPatNetworking

struct ModernSettingsView: View {
    let modelRouter: ModelRouter
    @State private var selectedCategory: SettingsCategory = .provider
    @AppStorage("yunpat.appearance") private var appearanceMode: AppearanceMode = .system
    @AppStorage("yunpat.autoDistill") private var autoDistill: Bool = true
    @AppStorage("yunpat.confirmToolCalls") private var confirmToolCalls: Bool = false
    @AppStorage("yunpat.defaultTopModule") private var defaultTopModule: String = "agent"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentPane
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("设置")
                .font(FontStyle.headline)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(SettingsCategory.allCases) { category in
                        categoryRow(category)
                    }
                }
                .padding(.horizontal, Spacing.sm)
            }

            Spacer()
        }
        .frame(width: 180)
        .background(Color.appSurfacePrimary)
    }

    private func categoryRow(_ category: SettingsCategory) -> some View {
        Button {
            withAccessibleAnimation(reduceMotion: reduceMotion, duration: AnimationDuration.fast) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: category.icon)
                    .font(.system(size: IconSize.sidebar))
                    .frame(width: 20, alignment: .center)
                Text(category.title)
                    .font(FontStyle.callout)
                Spacer()
            }
            .foregroundStyle(selectedCategory == category ? Color.accentColor : .primary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs + 2)
            .background(
                selectedCategory == category
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
    }

    private var contentPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(selectedCategory.title)
                    .font(FontStyle.title2)
                    .padding(.bottom, Spacing.xs)

                switch selectedCategory {
                case .provider:
                    ProviderSettingsView(modelRouter: modelRouter)
                case .skills:
                    SkillSettingsView()
                case .plugins:
                    PluginSettingsView()
                case .mcp:
                    MCPSettingsView()
                case .knowledge:
                    KnowledgeSettingsView()
                case .routing:
                    RoutingSettingsView()
                case .appearance:
                    appearanceSection
                case .workflow:
                    workflowSection
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appBackground)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            settingsCard(icon: "paintbrush", title: "外观") {
                Picker("主题", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                .help("选择应用的显示主题")
            }
        }
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            settingsCard(icon: "arrow.2.squarepath", title: "会话工作流") {
                Toggle("自动蒸馏长期记忆", isOn: $autoDistill)
                    .help("启用后，长期记忆将定期自动蒸馏以减少冗余")
                Toggle("执行工具前请求确认", isOn: $confirmToolCalls)
                    .help("启用后，每次工具调用前都会弹出确认对话框")

                Picker("默认顶部模块", selection: $defaultTopModule) {
                    Text("智能体").tag("agent")
                    Text("文件").tag("files")
                    Text("技能").tag("skills")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                .help("选择应用启动时默认显示的模块")
            }
        }
    }

    private func settingsCard<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: IconSize.inlineSmall))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(FontStyle.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                content()
            }
        }
        .padding(Spacing.md)
        .appCard()
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case provider
    case skills
    case plugins
    case mcp
    case knowledge
    case routing
    case appearance
    case workflow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .provider: "接口"
        case .skills: "技能"
        case .plugins: "插件"
        case .mcp: "MCP"
        case .knowledge: "知识库"
        case .routing: "路由"
        case .appearance: "外观"
        case .workflow: "工作流"
        }
    }

    var icon: String {
        switch self {
        case .provider: "key"
        case .skills: "wand.and.stars"
        case .plugins: "puzzlepiece.extension"
        case .mcp: "server.rack"
        case .knowledge: "books.vertical"
        case .routing: "chart.pie"
        case .appearance: "paintbrush"
        case .workflow: "arrow.2.squarepath"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    /// 转换为 SwiftUI ColorScheme；跟随系统时返回 nil 让系统接管。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
