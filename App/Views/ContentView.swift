import SwiftUI
import YunPatNetworking

struct ContentView: View {
    @StateObject private var tabManager = TabManager()
    @StateObject private var chatVM: ChatViewModel

    init(router: ModelRouter) {
        _chatVM = StateObject(wrappedValue: ChatViewModel(modelRouter: router))
    }

    var body: some View {
        VStack(spacing: 0) {
            TabBar(tabManager: tabManager)
                .padding(.horizontal)
                .padding(.top, 4)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let activeID = tabManager.activeTabID,
                           let activeTab = tabManager.tabs.first(where: { $0.id == activeID }) {
                            ForEach(activeTab.messages) { message in
                                MessageBubble(message: message)
                            }
                        }
                    }
                    .padding()
                }
            }

            Divider()

            HStack {
                TextField("输入消息...", text: $chatVM.inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await chatVM.sendMessage(in: tabManager) } }
                Button("发送") { Task { await chatVM.sendMessage(in: tabManager) } }
                    .disabled(chatVM.isStreaming || chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
    }
}
