import SwiftUI
import YunPatCore

struct ChatArea: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var chatManager: ChatManager
    var onAttachFiles: () -> Void

    var body: some View {
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
            InputBar(
                chatManager: chatManager,
                tabManager: tabManager,
                onAttachFiles: onAttachFiles
            )
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

    private var activeTab: ChatTab? {
        guard let id = tabManager.activeTabID else { return nil }
        return tabManager.tabs.first(where: { $0.id == id })
    }

    private var activeTabChecklist: String? { activeTab?.todoChecklist }
    private var activeTabClarify: ClarifyRequest? { activeTab?.clarifyRequest }
}
