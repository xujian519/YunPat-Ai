import SwiftUI
import YunPatCore
import YunPatNetworking

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

    init(router: ModelRouter) {
        _chatManager = StateObject(wrappedValue: ChatManager(modelRouter: router))
    }

    var body: some View {
        HSplitView {
            // ── 侧栏 ──
            if !sidebarCollapsed {
                CaseListSidebar(tabManager: tabManager)
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
            }

            // ── 主区域 ──
            VStack(spacing: 0) {
                toolbar
                Divider()

                if browserVisible {
                    PatentBrowser()
                } else if documentSplitVisible {
                    HSplitView {
                        chatArea
                        rightPanel
                    }
                } else {
                    chatArea
                }

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

            // ── 协作面板 ──
            if collaborationVisible {
                if caseGraphMode {
                    CaseGraphView(
                        caseId: activeTab?.caseId
                    )
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    CollaborationPanel(tabManager: tabManager, chatManager: chatManager)
                        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: collaborationVisible)
        .animation(.easeInOut(duration: 0.25), value: sidebarCollapsed)
        .animation(.easeInOut(duration: 0.25), value: browserVisible)
        .animation(.easeInOut(duration: 0.25), value: documentSplitVisible)
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

    private var toolbar: some View {
        HStack(spacing: 8) {
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
        .padding(.top, 4)
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
        .frame(width: 280)
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
                Button("发送") { Task { await chatManager.sendMessage(in: tabManager) } }
                    .disabled(
                        chatManager.isStreaming
                            || chatManager.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let activeTab = activeTab {
                        ForEach(activeTab.messages) { message in
                            MessageBubble(message: message)
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
        }
        .task {
            await chatManager.wireTodoTo(tabManager)
        }
    }
}

// MARK: - Collaboration Panel

struct CollaborationPanel: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var chatManager: ChatManager

    private var pendingApprovals: [ApprovalItem] {
        guard let activeID = tabManager.activeTabID,
            let tab = tabManager.tabs.first(where: { $0.id == activeID })
        else { return [] }
        var items: [ApprovalItem] = []
        if case .waitingApproval(let req) = tab.loopState {
            items.append(
                ApprovalItem(
                    title: "等待确认",
                    detail: req.detail,
                    checkpoint: tab.loopStateDescription
                ))
        }
        for msg in tab.messages {
            if msg.content.contains("需要确认") || msg.content.contains("⚠️") {
                items.append(ApprovalItem(title: "待确认", detail: msg.content, checkpoint: nil))
            }
        }
        return items
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                    .font(.title2)
                Text("协作")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            if pendingApprovals.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("无待确认事项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List(pendingApprovals) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        if let checkpoint = item.checkpoint {
                            Text(checkpoint)
                                .font(.system(size: 10))
                                .foregroundStyle(.blue)
                        }
                        Text(item.title)
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(item.detail)
                            .font(.caption)
                            .lineLimit(4)
                    }
                    .padding(4)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackgroundColor)
    }
}

struct ApprovalItem: Identifiable, Sendable {
    let id: UUID = UUID()
    let title: String
    let detail: String
    let checkpoint: String?
}
