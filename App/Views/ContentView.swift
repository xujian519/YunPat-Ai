import SwiftUI
import YunPatNetworking
import YunPatCore

struct ContentView: View {
    @StateObject private var tabManager = TabManager()
    @StateObject private var chatManager: ChatManager
    @State private var sidebarCollapsed = false
    @State private var collaborationVisible = false

    init(router: ModelRouter) {
        _chatManager = StateObject(wrappedValue: ChatManager(modelRouter: router))
    }

    var body: some View {
        HSplitView {
            if !sidebarCollapsed {
                SidebarView(tabManager: tabManager)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
            }

            VStack(spacing: 0) {
                toolbar
                Divider()

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
                            .disabled(chatManager.isStreaming || chatManager.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding()
                }
            }

            if collaborationVisible {
                CollaborationPanel(tabManager: tabManager, chatManager: chatManager)
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 360)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: collaborationVisible)
        .animation(.easeInOut(duration: 0.25), value: sidebarCollapsed)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: { withAnimation { sidebarCollapsed.toggle() } }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("显示/隐藏侧栏")

            TabBar(tabManager: tabManager)

            Spacer()

            flowModePicker

            Button(action: { withAnimation { collaborationVisible.toggle() } }) {
                Image(systemName: "panel.right")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("显示/隐藏协作面板")
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var flowModePicker: some View {
        Picker("模式", selection: Binding(
            get: { activeTab?.loopPreference ?? .copilot },
            set: { newFlow in
                chatManager.setFlow(newFlow, in: tabManager)
            }
        )) {
            Label("Copilot", systemImage: "circle").tag(AgentFlow.copilot)
            Label("Guided", systemImage: "circle.dotted").tag(AgentFlow.guided)
            Label("FullAgent", systemImage: "circle.circle").tag(AgentFlow.fullAgent)
        }
        .pickerStyle(.segmented)
        .frame(width: 280)
        .help("Copilot: 直接响应 | Guided: 分步确认 | FullAgent: 自主五步")
    }

    // MARK: - Computed Properties

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

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var tabManager: TabManager

    var body: some View {
        VStack(spacing: 0) {
            Text("标签")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

            Divider()

            List(selection: $tabManager.activeTabID) {
                ForEach(tabManager.tabs) { tab in
                    HStack {
                        Image(systemName: tab.flowIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(tab.title)
                            .lineLimit(1)
                        Spacer()
                        Text(tab.flowLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .tag(tab.id)
                }
            }
            .listStyle(.sidebar)

            Spacer()

            Divider()
            HStack {
                Button(action: { tabManager.addTab() }) {
                    Label("新建", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(8)
        }
        .background(.thickMaterial)
    }
}

// MARK: - Collaboration Panel

struct CollaborationPanel: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var chatManager: ChatManager

    private var pendingApprovals: [ApprovalItem] {
        guard let activeID = tabManager.activeTabID,
              let tab = tabManager.tabs.first(where: { $0.id == activeID }) else { return [] }
        var items: [ApprovalItem] = []
        if case .waitingApproval(let req) = tab.loopState {
            items.append(ApprovalItem(
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

// MARK: - Approval Item

struct ApprovalItem: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
    let checkpoint: String?
}
