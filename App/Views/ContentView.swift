import SwiftUI
import YunPatCore
import YunPatNetworking

struct ContentView: View {
    @StateObject private var tabManager: TabManager = TabManager()
    @StateObject private var chatManager: ChatManager
    @StateObject private var workspaceManager: CaseWorkspaceManager = CaseWorkspaceManager()
    @State private var filePickerOpen: Bool = false
    @State private var showWizard: Bool = false
    @Binding var windowTitle: String

    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    init(router: ModelRouter, windowTitle: Binding<String>) {
        _chatManager = StateObject(wrappedValue: ChatManager(modelRouter: router))
        _windowTitle = windowTitle
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                leftDockSection
                mainSection
                rightDockSection
            }

            if appState.bottomDockVisible && appState.centerMode != .focusWriting {
                Divider()
                DocumentWorkspace()
                    .frame(minHeight: PanelWidth.bottomDockMinHeight, idealHeight: PanelWidth.bottomDockIdealHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if appState.centerMode != .focusWriting {
                Divider()
                StatusBar(
                    filePickerOpen: $filePickerOpen,
                    onSave: { /* TODO: 接入文档保存逻辑 */ },
                    onSync: { syncToAgent() }
                )
            }
        }
        .animation(.easeInOut(duration: AnimationDuration.slow), value: appState.leftDockVisible)
        .animation(.easeInOut(duration: AnimationDuration.slow), value: appState.rightDockVisible)
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

    // MARK: - Left Dock

    @ViewBuilder
    private var leftDockSection: some View {
        if appState.leftDockVisible && appState.centerMode != .focusWriting {
            switch appState.leftDockActivePanel {
            case .caseList:
                CaseListSidebar(tabManager: tabManager)
                    .frame(
                        minWidth: PanelWidth.sidebarMin,
                        idealWidth: PanelWidth.sidebarIdeal,
                        maxWidth: PanelWidth.sidebarMax
                    )
            case .caseWorkspace:
                CaseWorkspaceView(manager: workspaceManager, tabManager: tabManager)
                    .frame(minWidth: PanelWidth.caseWorkspaceMin, idealWidth: PanelWidth.caseWorkspaceIdeal)
            case .knowledge:
                EmptyStateView(
                    icon: "books.vertical",
                    title: "知识库",
                    subtitle: "连接 Obsidian Vault 后自动加载法规与判例",
                    action: nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thickMaterial)
            }
        }
    }

    // MARK: - Main Section

    private var mainSection: some View {
        VStack(spacing: 0) {
            if appState.centerMode != .focusWriting {
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
        }
    }

    // MARK: - Right Dock

    @ViewBuilder
    private var rightDockSection: some View {
        if appState.rightDockVisible && appState.centerMode != .focusWriting {
            switch appState.rightDockActivePanel {
            case .collaboration:
                CollaborationPanel(tabManager: tabManager, chatManager: chatManager)
                    .frame(
                        minWidth: PanelWidth.collaborationMin,
                        idealWidth: PanelWidth.collaborationIdeal,
                        maxWidth: PanelWidth.collaborationMax
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .caseGraph:
                CaseGraphView(caseId: activeTab?.caseId)
                    .frame(
                        minWidth: PanelWidth.collaborationMin,
                        idealWidth: PanelWidth.collaborationIdeal,
                        maxWidth: PanelWidth.collaborationMax
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
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
                    LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                        let messages: [ChatMessage] = tab.messages
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            let isLast: Bool = index == messages.count - 1
                            MessageBubble(
                                message: message,
                                isStreaming: isLast && chatManager.isStreaming && message.role == .assistant
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                } else {
                    EmptyStateView(
                        icon: "bubble.left.and.bubble.right",
                        title: "开始对话",
                        subtitle: "发送消息，让 YunPat-Ai 协助你的专利代理工作",
                        action: nil
                    )
                    .padding(.top, Spacing.xl)
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
        chatManager.isStreaming || chatManager.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
