import SwiftUI
import YunPatCore
import YunPatNetworking

struct ContentView: View {
    @StateObject private var tabManager: TabManager = TabManager()
    @StateObject private var chatManager: ChatManager
    @StateObject private var workspaceManager: CaseWorkspaceManager = CaseWorkspaceManager()
    @State private var filePickerOpen: Bool = false
    @State private var showWizard: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Binding var windowTitle: String

    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    init(router: ModelRouter, windowTitle: Binding<String>) {
        _chatManager = StateObject(wrappedValue: ChatManager(modelRouter: router))
        _windowTitle = windowTitle
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebarContent
                    .navigationSplitViewColumnWidth(
                        min: PanelWidth.sidebarMin,
                        ideal: PanelWidth.sidebarIdeal,
                        max: PanelWidth.sidebarMax
                    )
            } content: {
                mainSection
            } detail: {
                detailContent
            }
            .toolbar { toolbarContent }

            if appState.bottomDockVisible && appState.centerMode != .focusWriting {
                Divider()
                DocumentWorkspace()
                    .frame(minHeight: PanelWidth.bottomDockMinHeight, idealHeight: PanelWidth.bottomDockIdealHeight)
                    .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            .easeInOut(duration: AnimationDuration.slow),
            value: appState.bottomDockVisible || appState.centerMode == .focusWriting
        )
        .animation(.easeInOut(duration: AnimationDuration.slow), value: appState.centerMode)
        .modifier(ContentViewModifiers(
            windowTitle: $windowTitle,
            tabManager: tabManager,
            chatManager: chatManager,
            showWizard: $showWizard,
            filePickerOpen: $filePickerOpen
        ))
        .fileImporter(
            isPresented: $filePickerOpen,
            allowedContentTypes: [.plainText, .pdf, .data],
            allowsMultipleSelection: true,
            onCompletion: handleFileImport
        )
        .onChange(of: appState.leftDockVisible) { _, _ in
            syncColumnVisibility()
        }
        .onChange(of: appState.rightDockVisible) { _, _ in
            syncColumnVisibility()
        }
        .onChange(of: activeTab?.caseId) { _, newCaseId in
            workspaceManager.selectedCaseId = newCaseId
        }
        .onChange(of: activeTab?.title) { _, newTitle in
            windowTitle = newTitle ?? "YunPat-Ai"
        }
        .task {
            workspaceManager.selectedCaseId = activeTab?.caseId
            windowTitle = activeTab?.title ?? "YunPat-Ai"
        }
        .withWindowRestoration()
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        if appState.leftDockVisible && appState.centerMode != .focusWriting {
            ProjectListSidebar(tabManager: tabManager)
        }
    }

    // MARK: - Main Section

    private var mainSection: some View {
        VStack(spacing: 0) {
            if appState.centerMode == .chat || appState.centerMode == .browser {
                TabStripContent(
                    tabManager: tabManager,
                    chatManager: chatManager
                )
                Divider()
            }
            centerContent
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        switch appState.centerMode {
        case .chat:
            chatArea
        case .browser:
            PatentBrowser()
        case .focusWriting:
            FocusWritingContent(onExit: { appState.exitFocusWriting() })
        case .files:
            FileBrowserView(workspaceManager: workspaceManager, tabManager: tabManager)
        case .skills:
            SkillGalleryView()
        case .routing:
            RoutingDashboardView()
        case .memory:
            MemoryDashboardView()
        case .alwaysOn:
            AlwaysOnDashboardView()
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if appState.rightDockVisible && appState.centerMode != .focusWriting {
            switch appState.rightDockActivePanel {
            case .collaboration:
                CollaborationPanel(tabManager: tabManager, chatManager: chatManager)
                    .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
            case .caseGraph:
                CaseGraphView(caseId: activeTab?.caseId)
                    .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
            case .costDashboard:
                CostDashboardView(caseId: activeTab?.caseId)
                    .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
            case .memoryAudit:
                MemoryAuditView()
                    .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
            case .toolAudit:
                ToolAuditView()
                    .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        VStack(spacing: 0) {
            messageList
            if let checklist = activeTabChecklist, !checklist.isEmpty {
                ChecklistView(markdown: checklist).padding(.horizontal)
            }
            if chatManager.clarifying, let req = activeTabClarify {
                ClarifyOverlay(
                    request: ClarifyRequestDisplay(from: req),
                    onAnswer: { answer in
                        Task { await chatManager.answerClarify(answer, in: tabManager) }
                    },
                    onDismiss: { chatManager.dismissClarify(in: tabManager) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            InputBar(chatManager: chatManager, tabManager: tabManager)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let tab = activeTab, !tab.messages.isEmpty {
                    messageStack(tab: tab)
                } else {
                    ChatWelcomeView { prompt in
                        chatManager.inputText = prompt
                        Task { await chatManager.sendMessage(in: tabManager) }
                    }
                }
            }
            .onChange(of: activeTab?.messages.count ?? 0) { _, _ in
                scrollToLast(proxy)
            }
            .onChange(of: activeTab?.messages.last?.content ?? "") { _, _ in
                scrollToLast(proxy)
            }
        }
        .task { await chatManager.wireTodoTo(tabManager) }
    }

    private func messageStack(tab: ChatTab) -> some View {
        LazyVStack(alignment: .leading, spacing: Spacing.sm) {
            let messages: [ChatMessage] = tab.messages
            let lastIndex: Int = messages.count - 1
            let isStreamingLast: Bool = chatManager.isStreaming
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                let isLast: Bool = index == lastIndex
                let shouldStream: Bool = isLast && isStreamingLast && message.role == .assistant
                MessageBubble(
                    message: message,
                    isStreaming: shouldStream
                )
                .id(message.id)
            }
        }
        .padding()
    }

    private func scrollToLast(_ proxy: ScrollViewProxy) {
        if let lastID = activeTab?.messages.last?.id {
            withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
        }
    }

    // MARK: - Helpers

    private var activeTab: ChatTab? {
        guard let id = tabManager.activeTabID else { return nil }
        return tabManager.tabs.first(where: { $0.id == id })
    }

    private var activeTabChecklist: String? { activeTab?.todoChecklist }
    private var activeTabClarify: ClarifyRequest? { activeTab?.clarifyRequest }

    private func syncColumnVisibility() {
        withAnimation(.easeInOut(duration: AnimationDuration.slow)) {
            if appState.leftDockVisible {
                columnVisibility = .all
            } else {
                columnVisibility = .doubleColumn
            }
        }
    }

    private func syncToAgent() {
        Task { await chatManager.sendDocumentAnnotations(in: tabManager) }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                Task { @MainActor in
                    let safe: String
                    do {
                        safe = try String(contentsOf: url, encoding: .utf8)
                    } catch {
                        safe = "二进制文件（无法读取文本内容）"
                    }
                    let name: String = url.lastPathComponent
                    let msg: String = "已打开: \(name)\n\n\(safe.prefix(2000))"
                    if let id = tabManager.activeTabID {
                        tabManager.appendMessage(to: id, ChatMessage(role: .user, content: msg))
                        await chatManager.sendMessage(in: tabManager)
                    }
                }
            }
        }
    }
}

// MARK: - Toolbar Extension

extension ContentView {
    @ToolbarContentBuilder
    fileprivate var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            ForEach(TopModule.allCases) { module in
                Button {
                    switchToModule(module)
                } label: {
                    Image(systemName: module.icon)
                }
                .help(module.rawValue)
                .foregroundStyle(appState.topModule == module ? Color.accentColor : Color.appTextSecondary)
            }
        }
    }

    private func switchToModule(_ module: TopModule) {
        withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
            appState.topModule = module
            switch module {
            case .agent:    appState.centerMode = .chat
            case .files:    appState.centerMode = .files
            case .skills:   appState.centerMode = .skills
            case .routing:  appState.centerMode = .routing
            case .memory:   appState.centerMode = .memory
            case .alwaysOn: appState.centerMode = .alwaysOn
            }
        }
    }
}

// MARK: - Extracted Subviews

struct FocusWritingContent: View {
    var onExit: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DocumentWorkspace().frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(duration: AnimationDuration.spring)) {
                            onExit()
                        }
                    } label: {
                        Label("退出专注模式", systemImage: "xmark.circle.fill")
                            .font(FontStyle.body)
                    }
                    .buttonStyle(.plain)
                    .padding(Spacing.sm)
                    .background(.ultraThinMaterial)
                    .cornerRadius(CornerRadius.lg)
                    .padding(Spacing.xs)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("退出专注写作模式 (ESC)")
                }
            }
        }
    }
}

struct InputBar: View {
    @ObservedObject var chatManager: ChatManager
    @ObservedObject var tabManager: TabManager
    @FocusState private var isInputFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            TextField("向 YunPat-Ai 发送消息…", text: $chatManager.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(FontStyle.body)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .accessibilityLabel("消息输入框")
                .onSubmit {
                    if !sendDisabled {
                        Task { await chatManager.sendMessage(in: tabManager) }
                    }
                }

            Button {
                Task { await chatManager.sendMessage(in: tabManager) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: IconSize.toolbar, weight: .semibold))
                    .foregroundStyle(sendDisabled ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.white))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(sendDisabled ? Color.appSurfaceTertiary : Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .disabled(sendDisabled)
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityLabel("发送消息")
            .help("⌘ + Enter 发送")
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(Color.appInputBarBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xl)
                        .stroke(isInputFocused ? Color.accentColor.opacity(0.5) : Color.appSeparator, lineWidth: 1)
                )
        )
        .padding(Spacing.sm)
    }

    private var sendDisabled: Bool {
        let trimmed: String = chatManager.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return chatManager.isStreaming || trimmed.isEmpty
    }
}
