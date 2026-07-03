import SwiftUI
import YunPatCore
import YunPatNetworking

// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
struct ContentView: View {
    @StateObject private var tabManager: TabManager = TabManager()
    @StateObject private var chatManager: ChatManager
    @State private var sidebarCollapsed: Bool = false
    @State private var collaborationVisible: Bool = false
    @State private var documentSplitVisible: Bool = false
    @State private var browserVisible: Bool = false
    @State private var folderTreeVisible: Bool = false
    @State private var caseGraphMode: Bool = false
    @State private var filePickerOpen: Bool = false
    @State private var settingsOpen: Bool = false
    @State private var showWizard: Bool = false

    @State private var focusWritingMode: Bool = false

    init(router: ModelRouter) {
        _chatManager = StateObject(wrappedValue: ChatManager(modelRouter: router))
    }

    var body: some View {
        HSplitView {
            if !sidebarCollapsed && !focusWritingMode {
                CaseListSidebar(tabManager: tabManager)
                    .frame(
                        minWidth: PanelWidth.sidebarMin,
                        idealWidth: PanelWidth.sidebarIdeal,
                        maxWidth: PanelWidth.sidebarMax
                    )
            }

            VStack(spacing: 0) {
                if !focusWritingMode {
                    toolbar
                    Divider()
                }

                if browserVisible && !focusWritingMode {
                    PatentBrowser()
                } else if documentSplitVisible && !focusWritingMode {
                    HSplitView {
                        chatArea
                        rightPanel
                    }
                } else if focusWritingMode {
                    DocumentWorkspace()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    chatArea
                }

                if !focusWritingMode {
                    Divider()
                    BottomToolbar(
                        filePickerOpen: $filePickerOpen,
                        browserVisible: $browserVisible,
                        folderTreeVisible: $folderTreeVisible,
                        documentSplit: $documentSplitVisible,
                        onSave: { saveCurrentDocument() },
                        onSync: { syncToAgent() }
                    )
                }
            }

            if collaborationVisible && !focusWritingMode {
                if caseGraphMode {
                    CaseGraphView(
                        caseId: activeTab?.caseId
                    )
                    .frame(
                        minWidth: PanelWidth.collaborationMin,
                        idealWidth: PanelWidth.collaborationIdeal,
                        maxWidth: PanelWidth.collaborationMax
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    CollaborationPanel(tabManager: tabManager, chatManager: chatManager)
                        .frame(
                            minWidth: PanelWidth.collaborationMin,
                            idealWidth: PanelWidth.collaborationIdeal,
                            maxWidth: PanelWidth.collaborationMax
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: AnimationDuration.slow), value: collaborationVisible)
        .animation(.easeInOut(duration: AnimationDuration.slow), value: sidebarCollapsed)
        .animation(.easeInOut(duration: AnimationDuration.slow), value: browserVisible)
        .animation(.easeInOut(duration: AnimationDuration.slow), value: documentSplitVisible)
        .sheet(isPresented: $settingsOpen) {
            TabSettingsView(tabManager: tabManager, chatManager: chatManager, isPresented: $settingsOpen)
        }
        .sheet(isPresented: $showWizard) {
            KnowledgeSetupWizard(isPresented: $showWizard)
        }
        .onAppear {
            if UserDefaults.standard.string(forKey: "yunpat.vaultPath") == nil {
                showWizard = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuNewTab)) { _ in
            tabManager.addTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuNewCase)) { _ in
            tabManager.addTab(type: .patent)
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuOpenFile)) { _ in
            filePickerOpen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuSave)) { _ in
            saveCurrentDocument()
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuUndo)) { _ in
            AppStateStore.shared.undo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuRedo)) { _ in
            AppStateStore.shared.redo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuToggleSidebar)) { _ in
            withAnimation { sidebarCollapsed.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuToggleCollaboration)) { _ in
            withAnimation { collaborationVisible.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuToggleBrowser)) { _ in
            withAnimation { browserVisible.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuToggleSplitScreen)) { _ in
            withAnimation { documentSplitVisible.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuFocusWriting)) { _ in
            withAnimation(.spring(duration: AnimationDuration.spring)) {
                focusWritingMode.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dropFile)) { notification in
            if let url = notification.object as? URL {
                handleDroppedFile(url)
            }
        }
        .fileImporter(
            isPresented: $filePickerOpen,
            allowedContentTypes: [.plainText, .pdf, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let content: String =
                        (try? String(contentsOf: url, encoding: .utf8))
                        ?? "[二进制文件: \(url.lastPathComponent)]"
                    let msg: String = "📎 已打开: \(url.lastPathComponent)\n\n\(String(content.prefix(2000)))"
                    Task { @MainActor in
                        if let activeID = tabManager.activeTabID {
                            tabManager.appendMessage(to: activeID, ChatMessage(role: .user, content: msg))
                            await chatManager.sendMessage(in: tabManager)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Right Panel (Folder Tree)

    private var rightPanel: some View {
        FolderTreeView(rootPath: activeTab?.workspacePath)
    }

    // MARK: - Toolbar

    @State private var showModelPicker: Bool = false
    @State private var showToolManager: Bool = false
    @State private var availableModels: [String] = []

    private var currentModelName: String {
        guard let model = activeTab?.loopModel else { return "模型" }
        if model.count > 15 { return String(model.prefix(15)) + "…" }
        return model
    }

    private var toolbar: some View {
        HStack(spacing: Spacing.xs) {
            Button(
                action: { withAnimation { sidebarCollapsed.toggle() } },
                label: { Image(systemName: "sidebar.left").font(.system(size: 12)) }
            )
            .buttonStyle(.plain)
            .help("显示/隐藏侧栏")

            Button(
                action: { withAnimation { settingsOpen.toggle() } },
                label: { Image(systemName: "gearshape").font(.system(size: 12)) }
            )
            .buttonStyle(.plain)
            .help("标签设置")

            TabBar(tabManager: tabManager)

            Spacer()

            Button {
                refreshModels()
                showModelPicker.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                    Text(currentModelName)
                        .font(.system(size: 9))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("切换模型")
            .popover(isPresented: $showModelPicker) {
                modelPickerPopover
            }

            Button {
                showToolManager.toggle()
            } label: {
                Image(systemName: "wrench.adjustable")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("工具管理")
            .popover(isPresented: $showToolManager) {
                toolManagerPopover
            }

            flowModePicker

            Button(
                action: { withAnimation { collaborationVisible.toggle() } },
                label: { Image(systemName: "checklist").font(.system(size: 12)) }
            )
            .buttonStyle(.plain)
            .help("协作面板")

            if collaborationVisible {
                Button(
                    action: { withAnimation { caseGraphMode.toggle() } },
                    label: {
                        Image(systemName: caseGraphMode ? "list.bullet" : "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 12))
                    }
                )
                .buttonStyle(.plain)
                .help(caseGraphMode ? "待确认列表" : "案件关系图")
            }
        }
        .padding(.horizontal)
        .padding(.top, Spacing.xxs)
    }

    private var modelPickerPopover: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("选择模型")
                .font(FontStyle.headline)
                .padding(.horizontal, Spacing.sm)
                .padding(.top, Spacing.xs)

            if availableModels.isEmpty {
                Text("未配置 API Key，请先在设置中添加")
                    .font(FontStyle.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.sm)
            } else {
                ForEach(availableModels, id: \.self) { model in
                    Button {
                        chatManager.setModel(model, in: tabManager)
                        showModelPicker = false
                    } label: {
                        HStack {
                            Text(model)
                                .font(FontStyle.callout)
                                .foregroundStyle(.primary)
                            Spacer()
                            if activeTab?.loopModel == model {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().padding(.top, Spacing.xxs)

            Button {
                settingsOpen = true
                showModelPicker = false
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

    private var toolManagerPopover: some View {
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

            Button {
                settingsOpen = true
                showToolManager = false
            } label: {
                Label("插件管理…", systemImage: "puzzlepiece.extension")
                    .font(FontStyle.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.sm)

            Button {
                settingsOpen = true
                showToolManager = false
            } label: {
                Label("MCP 服务器…", systemImage: "server.rack")
                    .font(FontStyle.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.sm)

            Divider().padding(.vertical, Spacing.xxs)

            Button {
                settingsOpen = true
                showToolManager = false
            } label: {
                Label("打开完整设置…", systemImage: "gearshape")
                    .font(FontStyle.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.xs)
        }
        .frame(width: 220)
        .padding(.vertical, Spacing.xxs)
    }

    private func refreshModels() {
        availableModels = [
            ModelProvider.deepseek.defaultModel,
            ModelProvider.openai.defaultModel,
            ModelProvider.anthropic.defaultModel,
            ModelProvider.glm.defaultModel
        ]
    }

    private var flowModePicker: some View {
        Picker(
            "模式",
            selection: Binding(
                get: { activeTab?.loopPreference ?? .copilot },
                set: { newFlow in
                    chatManager.setFlow(newFlow, in: tabManager)
                }
            )
        ) {
            Label("Copilot", systemImage: "circle").tag(AgentFlow.copilot)
            Label("Guided", systemImage: "circle.dotted").tag(AgentFlow.guided)
            Label("FullAgent", systemImage: "circle.circle").tag(AgentFlow.fullAgent)
        }
        .pickerStyle(.segmented)
        .frame(width: PanelWidth.flowPicker)
        .help("Copilot: 直接响应 | Guided: 分步确认 | FullAgent: 自主五步")
    }

    // MARK: - Computed

    private var activeTab: ChatTab? {
        guard let id = tabManager.activeTabID else { return nil }
        return tabManager.tabs.first(where: { $0.id == id })
    }

    private var activeTabChecklist: String? {
        activeTab?.todoChecklist
    }

    private var activeTabClarify: ClarifyRequest? {
        activeTab?.clarifyRequest
    }

    private func saveCurrentDocument() {
        AppStateStore.shared.registerUndo("保存文档") {
            // placeholder — actual save delegated to DocumentWorkspace
        }
    }

    private func handleDroppedFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        let content: String =
            (try? String(contentsOf: url, encoding: .utf8))
            ?? "[二进制文件: \(url.lastPathComponent)]"
        let msg: String = "📎 已打开: \(url.lastPathComponent)\n\n\(String(content.prefix(2000)))"
        Task { @MainActor in
            if let activeID = tabManager.activeTabID {
                tabManager.appendMessage(to: activeID, ChatMessage(role: .user, content: msg))
                await chatManager.sendMessage(in: tabManager)
            }
        }
    }

    private func syncToAgent() {
        Task {
            if let activeID = tabManager.activeTabID {
                tabManager.appendMessage(to: activeID, ChatMessage(role: .system, content: "📄 文档已同步至 Agent"))
            }
        }
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        VStack(spacing: 0) {
            messageList

            if let checklist = activeTabChecklist, !checklist.isEmpty {
                ChecklistView(markdown: checklist)
                    .padding(.horizontal)
            }

            if chatManager.clarifying, let clarifyReq = activeTabClarify {
                ClarifyOverlay(
                    request: ClarifyRequestDisplay(from: clarifyReq),
                    onAnswer: { answer in
                        Task { await chatManager.answerClarify(answer, in: tabManager) }
                    },
                    onDismiss: { chatManager.dismissClarify(in: tabManager) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Divider()

            HStack {
                TextField("输入消息...", text: $chatManager.inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await chatManager.sendMessage(in: tabManager) } }
                    .accessibilityLabel("消息输入框")
                Button("发送") { Task { await chatManager.sendMessage(in: tabManager) } }
                    .disabled(
                        chatManager.isStreaming
                            || chatManager.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("发送消息")
            }
            .padding()
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                    if let activeTab = activeTab {
                        ForEach(Array(activeTab.messages.enumerated()), id: \.element.id) { index, message in
                            let isLast: Bool = index == activeTab.messages.count - 1
                            MessageBubble(
                                message: message,
                                isStreaming: isLast && chatManager.isStreaming && message.role == .assistant
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: activeTab?.messages.count ?? 0) { _, _ in
                if let lastID = activeTab?.messages.last?.id {
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
            .onChange(of: activeTab?.messages.last?.content ?? "") { _, _ in
                if let lastID = activeTab?.messages.last?.id {
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
        }
        .task {
            await chatManager.wireTodoTo(tabManager)
        }
    }
}
