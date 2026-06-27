import SwiftUI
import YunPatNetworking

struct ContentView: View {
    @StateObject private var tabManager = TabManager()
    @StateObject private var chatVM: ChatViewModel
    @State private var sidebarCollapsed = false
    @State private var collaborationVisible = false

    init(router: ModelRouter) {
        _chatVM = StateObject(wrappedValue: ChatViewModel(modelRouter: router))
    }

    var body: some View {
        HSplitView {
            // 左区：侧栏（案件/标签列表）
            if !sidebarCollapsed {
                SidebarView(tabManager: tabManager)
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
            }

            // 中区：主工作区（TabBar + 消息列表 + 输入栏）
            VStack(spacing: 0) {
                // 顶部工具栏：侧栏切换 + 标签栏
                HStack(spacing: 8) {
                    Button(action: { withAnimation { sidebarCollapsed.toggle() } }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("显示/隐藏侧栏")

                    TabBar(tabManager: tabManager)

                    Button(action: { withAnimation { collaborationVisible.toggle() } }) {
                        Image(systemName: "panel.right")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("显示/隐藏协作面板")
                }
                .padding(.horizontal)
                .padding(.top, 4)

                Divider()

                // 消息列表
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if let activeID = tabManager.activeTabID,
                               let activeTab = tabManager.tabs.first(where: { $0.id == activeID }) {
                                ForEach(activeTab.messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: tabManager.tabs.first(where: { $0.id == tabManager.activeTabID })?.messages.count) { _, _ in
                        if let lastID = tabManager.tabs.first(where: { $0.id == tabManager.activeTabID })?.messages.last?.id {
                            withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                        }
                    }
                }

                Divider()

                // 输入栏
                HStack {
                    TextField("输入消息...", text: $chatVM.inputText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await chatVM.sendMessage(in: tabManager) } }
                    Button("发送") { Task { await chatVM.sendMessage(in: tabManager) } }
                        .disabled(chatVM.isStreaming || chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }

            // 右区：协作面板（默认隐藏，有待确认项时显示）
            if collaborationVisible {
                CollaborationPanelPlaceholder()
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 360)
            }
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
                        Image(systemName: "bubble.left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(tab.title)
                            .lineLimit(1)
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
        .background(Color.windowBackgroundColor)
    }
}

// MARK: - Collaboration Panel (Placeholder for Plan 2)

struct CollaborationPanelPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("协作面板")
                .font(.headline)
            Text("待确认事项将在此显示")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackgroundColor)
    }
}
