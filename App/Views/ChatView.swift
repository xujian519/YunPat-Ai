import SwiftUI
import YunPatNetworking
import YunPatCore

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var isStreaming = false

    private let modelRouter: ModelRouter
    private let loopEngine: AgentLoopEngine
    private let requestQueue: GlobalRequestQueue

    init(modelRouter: ModelRouter, requestQueue: GlobalRequestQueue? = nil) {
        self.modelRouter = modelRouter
        self.loopEngine = AgentLoopEngine(modelRouter: modelRouter)
        // 全局共享队列：未传入时自动创建默认配置（max 3 并发）
        self.requestQueue = requestQueue ?? GlobalRequestQueue()
    }

    func sendMessage(in tabManager: TabManager) async {
        guard let activeID = tabManager.activeTabID,
              !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: inputText)
        tabManager.appendMessage(to: activeID, userMessage)
        let sentText = inputText
        inputText = ""
        isStreaming = true

        do {
            let result = try await loopEngine.run(request: UserRequest(content: sentText), flow: .copilot)
            switch result {
            case .completed(let text):
                tabManager.appendMessage(to: activeID, ChatMessage(role: .assistant, content: text))
            default:
                handleLoopResult(result)
            }
        } catch {
            tabManager.appendMessage(to: activeID, ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)"))
        }
        isStreaming = false
    }

    func handleLoopResult(_ result: LoopResult) {
        switch result {
        case .needsClarification(let questions):
            let items = questions.map { ApprovalItem(title: "需要澄清", detail: $0, checkpoint: "facts") }
            NotificationCenter.default.post(name: .pendingApprovalsChanged, object: items)
        case .needsRevision(let issues):
            let items = issues.map { ApprovalItem(title: "需要修正", detail: $0.description, checkpoint: "review") }
            NotificationCenter.default.post(name: .pendingApprovalsChanged, object: items)
        default: break
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            Text(message.content)
                .padding(10)
                .background(message.role == .user ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .textSelection(.enabled)
            if message.role == .assistant { Spacer() }
        }
    }
}

extension Notification.Name {
    static let pendingApprovalsChanged = Notification.Name("pendingApprovalsChanged")
}
