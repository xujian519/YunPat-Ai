import SwiftUI
import YunPatCore
import YunPatNetworking

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
    @State private var showWizard: Bool = false
    @State private var focusWritingMode: Bool = false
    @Binding var windowTitle: String

    init(router: ModelRouter, windowTitle: Binding<String>) {
        _chatManager = StateObject(wrappedValue: ChatManager(modelRouter: router))
        _windowTitle = windowTitle
    }

    var body: some View {
        HSplitView {
            sidebarSection
            mainSection
            collaborationSection
        }
        .animation(.easeInOut(duration: AnimationDuration.slow), value: collaborationVisible)
        .animation(.easeInOut(duration: AnimationDuration.slow), value: sidebarCollapsed)
        .animation(.easeInOut(duration: AnimationDuration.slow), value: browserVisible)
        .animation(.easeInOut(duration: AnimationDuration.slow), value: documentSplitVisible)
        .modifier(ContentViewModifiers(
            windowTitle: $windowTitle,
            tabManager: tabManager,
            chatManager: chatManager,
            sidebarCollapsed: $sidebarCollapsed,
            collaborationVisible: $collaborationVisible,
            documentSplitVisible: $documentSplitVisible,
            browserVisible: $browserVisible,
            focusWritingMode: $focusWritingMode,
            showWizard: $showWizard,
            filePickerOpen: $filePickerOpen
        ))
        .fileImporter(
            isPresented: $filePickerOpen,
            allowedContentTypes: [.plainText, .pdf, .data],
            allowsMultipleSelection: true,
            onCompletion: handleFileImport
        )
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarSection: some View {
        if !sidebarCollapsed && !focusWritingMode {
            CaseListSidebar(tabManager: tabManager)
                .frame(minWidth: PanelWidth.sidebarMin, idealWidth: PanelWidth.sidebarIdeal)
        }
    }

    // MARK: - Main Section

    private var mainSection: some View {
        VStack(spacing: 0) {
            if !focusWritingMode {
                TabStripContent(
                    tabManager: tabManager,
                    chatManager: chatManager
                )
                Divider()
            }
            contentArea
            if !focusWritingMode {
                Divider()
                BottomToolbar(
                    filePickerOpen: $filePickerOpen,
                    browserVisible: $browserVisible,
                    folderTreeVisible: $folderTreeVisible,
                    documentSplit: $documentSplitVisible,
                    onSave: {},
                    onSync: { syncToAgent() }
                )
            }
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if browserVisible && !focusWritingMode {
            PatentBrowser()
        } else if documentSplitVisible && !focusWritingMode {
            HSplitView { chatArea; rightPanel }
        } else if focusWritingMode {
            FocusWritingContent(focusWritingMode: $focusWritingMode)
        } else {
            chatArea
        }
    }

    private var rightPanel: some View {
        FolderTreeView(rootPath: activeTab?.workspacePath)
    }

    // MARK: - Collaboration Section

    @ViewBuilder
    private var collaborationSection: some View {
        if collaborationVisible && !focusWritingMode {
            if caseGraphMode {
                CaseGraphView(caseId: activeTab?.caseId)
                    .frame(minWidth: PanelWidth.collaborationMin, idealWidth: PanelWidth.collaborationIdeal)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                CollaborationPanel(tabManager: tabManager, chatManager: chatManager)
                    .frame(minWidth: PanelWidth.collaborationMin, idealWidth: PanelWidth.collaborationIdeal)
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
                LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                    if let tab = activeTab {
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
                }
                .padding()
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
        Task {
            if let activeID = tabManager.activeTabID {
                tabManager.appendMessage(
                    to: activeID,
                    ChatMessage(role: .system, content: "文档已同步至 Agent")
                )
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                Task { @MainActor in
                    let raw: String? = try? String(contentsOf: url, encoding: .utf8)
                    let safe: String = raw ?? "二进制文件"
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
    @Binding var focusWritingMode: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DocumentWorkspace().frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(duration: AnimationDuration.spring)) {
                            focusWritingMode = false
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

    var body: some View {
        HStack {
            TextField("输入消息...", text: $chatManager.inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await chatManager.sendMessage(in: tabManager) } }
                .accessibilityLabel("消息输入框")
            Button("发送") {
                Task { await chatManager.sendMessage(in: tabManager) }
            }
            .disabled(sendDisabled)
            .accessibilityLabel("发送消息")
        }
        .padding()
    }

    private var sendDisabled: Bool {
        chatManager.isStreaming || chatManager.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
