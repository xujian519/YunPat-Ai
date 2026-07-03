import SwiftUI
import YunPatCore
import YunPatNetworking

struct TabStripContent: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var chatManager: ChatManager
    var activeTab: ChatTab?

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            ModelPickerButton(tabManager: tabManager, chatManager: chatManager)
            FlowModePicker(tabManager: tabManager, chatManager: chatManager)
            ToolManagerButton()
            CollaborationToggle()
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.top, Spacing.xxs)
    }
}

struct ModelPickerButton: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var chatManager: ChatManager
    @State private var showPicker: Bool = false

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain")
                    .font(.system(size: IconSize.inlineSmall))
                Text(currentModel)
                    .font(FontStyle.caption)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.08))
            .cornerRadius(CornerRadius.sm)
        }
        .buttonStyle(.plain)
        .help("切换模型")
        .popover(isPresented: $showPicker) {
            ModelPickerPopover(
                tabManager: tabManager,
                chatManager: chatManager,
                isPresented: $showPicker
            )
        }
    }

    private var currentModel: String {
        guard let model = activeTab?.loopModel else { return "模型" }
        if model.count > 15 { return String(model.prefix(15)) + "…" }
        return model
    }

    private var activeTab: ChatTab? {
        guard let id = tabManager.activeTabID else { return nil }
        return tabManager.tabs.first(where: { $0.id == id })
    }
}

struct ModelPickerPopover: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var chatManager: ChatManager
    @Binding var isPresented: Bool

    private let models: [String] = [
        ModelProvider.deepseek.defaultModel,
        ModelProvider.openai.defaultModel,
        ModelProvider.anthropic.defaultModel,
        ModelProvider.glm.defaultModel
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("选择模型")
                .font(FontStyle.headline)
                .padding(.horizontal, Spacing.sm)
                .padding(.top, Spacing.xs)

            ForEach(models, id: \.self) { model in
                Button {
                    chatManager.setModel(model, in: tabManager)
                    isPresented = false
                } label: {
                    HStack {
                        Text(model)
                            .font(FontStyle.callout)
                            .foregroundStyle(.primary)
                        Spacer()
                        if activeModel == model {
                            Image(systemName: "checkmark")
                                .font(FontStyle.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.top, Spacing.xxs)
            Button {
                isPresented = false
            } label: {
                Label("配置 API Key…", systemImage: "key")
                    .font(FontStyle.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.xs)
        }
        .frame(width: 250)
        .padding(.vertical, Spacing.xxs)
    }

    private var activeModel: String? {
        guard let id = tabManager.activeTabID,
              let tab = tabManager.tabs.first(where: { $0.id == id })
        else { return nil }
        return tab.loopModel
    }
}

struct FlowModePicker: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var chatManager: ChatManager

    var body: some View {
        Picker("模式", selection: flowBinding) {
            Label("Copilot", systemImage: "circle").tag(AgentFlow.copilot)
            Label("Guided", systemImage: "circle.dotted").tag(AgentFlow.guided)
            Label("FullAgent", systemImage: "circle.circle").tag(AgentFlow.fullAgent)
        }
        .pickerStyle(.segmented)
        .frame(width: PanelWidth.flowPicker)
        .help("Copilot: 直接响应 | Guided: 分步确认 | FullAgent: 自主五步")
    }

    private var flowBinding: Binding<AgentFlow> {
        Binding(
            get: { activePreference },
            set: { chatManager.setFlow($0, in: tabManager) }
        )
    }

    private var activePreference: AgentFlow {
        guard let id = tabManager.activeTabID,
              let tab = tabManager.tabs.first(where: { $0.id == id })
        else { return .copilot }
        return tab.loopPreference
    }
}

struct ToolManagerButton: View {
    @State private var showPopover: Bool = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "wrench.adjustable")
                .font(.system(size: IconSize.toolbar))
        }
        .buttonStyle(.plain)
        .help("工具管理")
        .popover(isPresented: $showPopover) {
            ToolManagerPopover(isPresented: $showPopover)
        }
    }
}

struct ToolManagerPopover: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("工具管理")
                .font(FontStyle.headline)
                .padding(.horizontal, Spacing.sm)
                .padding(.top, Spacing.xs)
            Text("已注册工具将在对话中自动被发现和调用")
                .font(FontStyle.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.sm)
            Divider().padding(.vertical, Spacing.xxs)
            SettingsLinkRow(label: "插件管理…", icon: "puzzlepiece.extension") {
                isPresented = false
            }
            SettingsLinkRow(label: "MCP 服务器…", icon: "server.rack") {
                isPresented = false
            }
            Divider().padding(.vertical, Spacing.xxs)
            SettingsLinkRow(label: "打开完整设置…", icon: "gearshape") {
                isPresented = false
            }
        }
        .frame(width: 220)
        .padding(.vertical, Spacing.xxs)
    }
}

private struct SettingsLinkRow: View {
    let label: String
    let icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(FontStyle.caption)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.sm)
    }
}

struct CollaborationToggle: View {
    var body: some View {
        Button(
            action: {},
            label: { Image(systemName: "checklist")
                .font(.system(size: IconSize.toolbar)) }
        )
        .buttonStyle(.plain)
        .help("协作面板")
    }
}
