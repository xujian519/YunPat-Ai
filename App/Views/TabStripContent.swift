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
    @State private var customModel: String = ""
    @State private var showCustomField: Bool = false

    private struct ModelSection {
        let title: String
        let icon: String
        let models: [(name: String, desc: String)]
    }

    private let sections: [ModelSection] = [
        ModelSection(title: "DeepSeek", icon: "bolt.fill", models: [
            ("deepseek-v4-flash", "V4 Flash 旗舰 1M 上下文"),
            ("deepseek-v4-pro", "V4 Pro 增强版"),
            ("deepseek-chat", "V4 Flash (旧名，兼容)"),
            ("deepseek-reasoner", "V4 Flash 思考模式 (旧名，兼容)")
        ]),
        ModelSection(title: "OpenAI", icon: "brain.head.profile", models: [
            ("gpt-4o", "GPT-4o 多模态旗舰"),
            ("gpt-4o-mini", "GPT-4o mini 经济型"),
            ("gpt-4-turbo", "GPT-4 Turbo"),
            ("o3-mini", "o3-mini 推理"),
            ("o1", "o1 深度推理")
        ]),
        ModelSection(title: "Anthropic", icon: "leaf.fill", models: [
            ("claude-sonnet-4-20250514", "Claude Sonnet 4 平衡"),
            ("claude-3-5-sonnet-20241022", "Claude 3.5 Sonnet"),
            ("claude-3-5-haiku-20241022", "Claude 3.5 Haiku 快速"),
            ("claude-opus-4-20250514", "Claude Opus 4 最强")
        ]),
        ModelSection(title: "GLM (智谱)", icon: "star.fill", models: [
            ("glm-4-plus", "GLM-4 Plus 增强"),
            ("glm-4", "GLM-4 标准"),
            ("glm-4-flash", "GLM-4 Flash 快速"),
            ("glm-4v", "GLM-4V 多模态"),
            ("glm-4-long", "GLM-4 Long 长上下文")
        ]),
        ModelSection(title: "Qwen (通义千问)", icon: "cloud.fill", models: [
            ("qwen-plus", "Qwen Plus 均衡"),
            ("qwen-max", "Qwen Max 最强"),
            ("qwen-turbo", "Qwen Turbo 快速"),
            ("qwen-vl-plus", "Qwen VL Plus 多模态")
        ]),
        ModelSection(title: "OpenRouter", icon: "arrow.triangle.branch", models: [
            ("openai/gpt-4o", "GPT-4o (通过 OpenRouter)"),
            ("anthropic/claude-sonnet-4", "Claude Sonnet 4 (通过 OpenRouter)"),
            ("google/gemini-2.5-flash", "Gemini 2.5 Flash (通过 OpenRouter)"),
            ("meta-llama/llama-3.3-70b", "Llama 3.3 70B (通过 OpenRouter)")
        ]),
        ModelSection(title: "SiliconFlow (硅基流动)", icon: "cpu", models: [
            ("Qwen/Qwen2.5-7B-Instruct", "Qwen 2.5 7B"),
            ("Qwen/Qwen2.5-14B-Instruct", "Qwen 2.5 14B"),
            ("deepseek-ai/DeepSeek-V3", "DeepSeek V3"),
            ("THUDM/glm-4-9b-chat", "GLM-4 9B")
        ]),
        ModelSection(title: "Mistral AI", icon: "wind", models: [
            ("mistral-large-latest", "Mistral Large 最新"),
            ("mistral-small-latest", "Mistral Small 快速"),
            ("codestral-latest", "Codestral 代码")
        ]),
        ModelSection(title: "Together AI", icon: "square.grid.3x3", models: [
            ("meta-llama/Llama-3.3-70B-Instruct-Turbo", "Llama 3.3 70B"),
            ("mistralai/Mixtral-8x7B-Instruct-v0.1", "Mixtral 8x7B"),
            ("deepseek-ai/DeepSeek-V3", "DeepSeek V3")
        ]),
        ModelSection(title: "MLX (本地)", icon: "macmini", models: [
            ("mlx-community/Qwen2.5-7B-Instruct-4bit", "Qwen 2.5 7B (4bit)"),
            ("mlx-community/Mistral-7B-Instruct-v0.3-4bit", "Mistral 7B (4bit)"),
            ("mlx-community/Llama-3.2-3B-Instruct-4bit", "Llama 3.2 3B (4bit)"),
            ("mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit", "DeepSeek R1 7B (4bit)")
        ]),
        ModelSection(title: "Ollama (本地)", icon: "desktopcomputer", models: [
            ("llama3", "Llama 3"),
            ("llama3:8b", "Llama 3 8B"),
            ("qwen2.5:7b", "Qwen 2.5 7B"),
            ("qwen2.5:32b", "Qwen 2.5 32B"),
            ("deepseek-r1:7b", "DeepSeek R1 7B"),
            ("deepseek-r1:14b", "DeepSeek R1 14B"),
            ("mistral", "Mistral"),
            ("mixtral:8x7b", "Mixtral 8x7B"),
            ("gemma2:9b", "Gemma 2 9B"),
            ("phi3:14b", "Phi-3 14B")
        ])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(sections.indices, id: \.self) { idx in
                        sectionView(sections[idx])
                        if idx < sections.count - 1 {
                            Divider().padding(.vertical, 2)
                        }
                    }

                    customSection
                }
                .padding(.vertical, Spacing.xxs)
            }
            .frame(maxHeight: 420)
        }
        .frame(width: 280)
    }

    private var headerView: some View {
        HStack {
            Text("选择模型")
                .font(FontStyle.headline)
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xs)
    }

    private func sectionView(_ section: ModelSection) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(section.title, systemImage: section.icon)
                .font(FontStyle.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 2)

            ForEach(section.models, id: \.name) { model in
                Button {
                    chatManager.setModel(model.name, in: tabManager)
                    isPresented = false
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.name)
                                .font(FontStyle.callout)
                                .foregroundStyle(.primary)
                            Text(model.desc)
                                .font(FontStyle.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if activeModel == model.name {
                            Image(systemName: "checkmark")
                                .font(FontStyle.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 3)
                    .background(
                        activeModel == model.name
                            ? Color.accentColor.opacity(0.08)
                            : Color.clear
                    )
                    .cornerRadius(CornerRadius.sm)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().padding(.vertical, 2)

            Button {
                withAnimation { showCustomField.toggle() }
            } label: {
                HStack {
                    Image(systemName: showCustomField ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                    Text("自定义模型")
                        .font(FontStyle.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            if showCustomField {
                HStack(spacing: 4) {
                    TextField("输入模型名称...", text: $customModel)
                        .textFieldStyle(.roundedBorder)
                        .font(FontStyle.caption)
                        .onSubmit { applyCustomModel() }
                    Button("确定") { applyCustomModel() }
                        .font(FontStyle.caption)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, 4)
            }

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
    }

    private func applyCustomModel() {
        let trimmed = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatManager.setModel(trimmed, in: tabManager)
        isPresented = false
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
            Label("自由问答", systemImage: "circle").tag(AgentFlow.copilot)
            Label("分步撰写", systemImage: "circle.dotted").tag(AgentFlow.guided)
            Label("自动代理", systemImage: "circle.circle").tag(AgentFlow.fullAgent)
        }
        .pickerStyle(.segmented)
        .frame(width: PanelWidth.flowPicker)
        .help("自由问答: 直接对话无需确认 | 分步撰写: 逐步确认适合专利稿 | 自动代理: 全自主完成复杂任务")
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
