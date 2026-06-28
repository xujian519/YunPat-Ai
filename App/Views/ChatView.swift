import SwiftUI
import YunPatNetworking
import YunPatCore

@MainActor
final class ChatManager: ObservableObject {
    @Published var inputText = ""
    @Published var isStreaming = false
    @Published var clarifying = false

    private let modelRouter: ModelRouter
    private let loopEngine: AgentLoopEngine
    private var patentLoopEngine: PatentLoopEngine?
    private let requestQueue: GlobalRequestQueue

    /// 待处理的 clarify 请求（由 sendMessage 后的结果触发）
    private var pendingClarify: ClarifyRequestDisplay? = nil

    init(modelRouter: ModelRouter, requestQueue: GlobalRequestQueue? = nil) {
        self.modelRouter = modelRouter
        self.loopEngine = AgentLoopEngine(modelRouter: modelRouter)
        self.requestQueue = requestQueue ?? GlobalRequestQueue()
    }

    /// 将 AgentLoopEngine 的 onTodoUpdate 回传桥接到 tabManager
    func wireTodoTo(_ tabManager: TabManager) async {
        await loopEngine.setOnTodoUpdate { [tabManager] checklist in
            Task { @MainActor in
                guard let activeID = tabManager.activeTabID,
                      let idx = tabManager.tabs.firstIndex(where: { $0.id == activeID }) else { return }
                tabManager.tabs[idx].todoChecklist = checklist
            }
        }
    }

    /// 获取当前待处理的 clarify 请求
    func currentClarifyRequest() -> ClarifyRequestDisplay? {
        pendingClarify
    }

    func sendMessage(in tabManager: TabManager) async {
        guard let activeID = tabManager.activeTabID,
              let idx = tabManager.tabs.firstIndex(where: { $0.id == activeID }),
              !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let tab = tabManager.tabs[idx]
        let userMessage = ChatMessage(role: .user, content: inputText)
        tabManager.appendMessage(to: activeID, userMessage)
        tabManager.tabs[idx].sessionMemory.append(Message(role: .user, content: inputText))
        let sentText = inputText
        inputText = ""
        isStreaming = true
        clarifying = false
        tabManager.tabs[idx].loopState = .running(step: "init")

        // 插入占位 assistant 消息供流式填充
        let placeholder = ChatMessage(role: .assistant, content: "")
        tabManager.appendMessage(to: activeID, placeholder)
        let capturedTabID = activeID

        // 流式回调：每收到文本增量，更新最后一条消息
        let onChunk: PatentLoopHooks.OnStreamChunk = { [tabManager] text in
            Task { @MainActor in
                guard let idx = tabManager.tabs.firstIndex(where: { $0.id == capturedTabID }),
                      let lastIdx = tabManager.tabs[idx].messages.indices.last else { return }
                tabManager.tabs[idx].messages[lastIdx].content += text
            }
        }

        do {
            let flow = tab.loopPreference
            let model = tab.loopModel

            switch flow {
            case .copilot, .guided:
                let history = tabManager.tabs[idx].sessionMemory.messages
                let result = try await loopEngine.run(
                    request: UserRequest(content: sentText),
                    flow: flow,
                    model: model,
                    history: history,
                    onStreamChunk: onChunk
                )
                tabManager.tabs[idx].loopState = .idle
                // 记录 assistant 回复到 sessionMemory
                if case .completed(let text) = result {
                    tabManager.tabs[idx].sessionMemory.append(Message(role: .assistant, content: text))
                }
                await handleLoopResult(result, activeID: activeID, in: tabManager, streamed: true)

            case .fullAgent:
                let history = tabManager.tabs[idx].sessionMemory.messages
                let result = try await getPatentLoopEngine().run(
                    request: UserRequest(content: sentText),
                    flow: .fullAgent,
                    history: history,
                    onStreamChunk: onChunk
                )
                tabManager.tabs[idx].loopState = .idle
                if case .completed(let text) = result {
                    tabManager.tabs[idx].sessionMemory.append(Message(role: .assistant, content: text))
                }
                await handleLoopResult(result, activeID: activeID, in: tabManager, streamed: true)
            }
        } catch {
            tabManager.tabs[idx].loopState = .idle
            // 用错误文本替换占位消息
            if let idx = tabManager.tabs.firstIndex(where: { $0.id == capturedTabID }),
               let lastIdx = tabManager.tabs[idx].messages.indices.last {
                let existing = tabManager.tabs[idx].messages[lastIdx].content
                tabManager.tabs[idx].messages[lastIdx].content = existing.isEmpty
                    ? "Error: \(error.localizedDescription)"
                    : existing + "\n\nError: \(error.localizedDescription)"
            }
        }
        isStreaming = false
    }

    private func handleLoopResult(_ result: LoopResult, activeID: UUID, in tabManager: TabManager, streamed: Bool = false) async {
        switch result {
        case .completed(let text):
            if !streamed {
                tabManager.appendMessage(to: activeID, ChatMessage(role: .assistant, content: text))
            }
            // 流式模式下文本已逐步追加，不需要再 append
        case .needsClarification(let questions):
            if let first = questions.first {
                pendingClarify = ClarifyRequestDisplay(question: first)
                clarifying = true
                if let idx = tabManager.tabs.firstIndex(where: { $0.id == activeID }) {
                    tabManager.tabs[idx].clarifyRequest = ClarifyRequest(
                        question: first, options: [], allowMultiple: false
                    )
                    tabManager.tabs[idx].loopState = .waitingApproval(
                        ApprovalRequest(summary: "需要澄清", detail: first)
                    )
                }
            }
        case .needsRevision(let issues):
            let msg = issues.map(\.description).joined(separator: "\n")
            tabManager.appendMessage(to: activeID, ChatMessage(role: .assistant, content: "需修正：\n\(msg)"))
        case .exceededRevisionLimit(let issues):
            let msg = issues.map(\.description).joined(separator: "\n")
            tabManager.appendMessage(to: activeID, ChatMessage(role: .assistant, content: "超过修订次数限制：\n\(msg)"))
        case .cancelled:
            tabManager.appendMessage(to: activeID, ChatMessage(role: .assistant, content: "已取消"))
        }
    }

    /// 用户对 clarify 做出回答后，将回答作为新消息发送
    func answerClarify(_ answer: String, in tabManager: TabManager) async {
        guard let activeID = tabManager.activeTabID,
              let idx = tabManager.tabs.firstIndex(where: { $0.id == activeID }) else { return }
        clarifying = false
        pendingClarify = nil
        tabManager.tabs[idx].clarifyRequest = nil

        let userMessage = ChatMessage(role: .user, content: answer)
        tabManager.appendMessage(to: activeID, userMessage)
        isStreaming = true
        tabManager.tabs[idx].loopState = .running(step: "executing")

        do {
            let flow = tabManager.tabs[idx].loopPreference
            let model = tabManager.tabs[idx].loopModel
            let result = try await loopEngine.run(
                request: UserRequest(content: answer),
                flow: flow,
                model: model,
                onStreamChunk: nil
            )
            tabManager.tabs[idx].loopState = .idle
            await handleLoopResult(result, activeID: activeID, in: tabManager)
        } catch {
            tabManager.tabs[idx].loopState = .idle
            tabManager.appendMessage(to: activeID, ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)"))
        }
        isStreaming = false
    }

    /// 取消 clarify
    func dismissClarify(in tabManager: TabManager) {
        guard let activeID = tabManager.activeTabID,
              let idx = tabManager.tabs.firstIndex(where: { $0.id == activeID }) else { return }
        clarifying = false
        pendingClarify = nil
        tabManager.tabs[idx].clarifyRequest = nil
    }

    /// 为当前 tab 设置 Agent Flow 模式
    func setFlow(_ flow: AgentFlow, in tabManager: TabManager) {
        guard let activeID = tabManager.activeTabID,
              let idx = tabManager.tabs.firstIndex(where: { $0.id == activeID }) else { return }
        tabManager.tabs[idx].loopPreference = flow
    }

    /// 为当前 tab 设置模型
    func setModel(_ model: String, in tabManager: TabManager) {
        guard let activeID = tabManager.activeTabID,
              let idx = tabManager.tabs.firstIndex(where: { $0.id == activeID }) else { return }
        tabManager.tabs[idx].loopModel = model
    }

    // MARK: - Patent Engine

    private func getPatentLoopEngine() -> PatentLoopEngine {
        if let existing = patentLoopEngine {
            return existing
        }
        let vaultPath = UserDefaults.standard.string(forKey: "yunpat.vaultPath") ?? ""
        let wiki = WikiAdapter(vaultPath: URL(filePath: vaultPath))
        let engine = PatentLoopEngine(modelRouter: modelRouter, wikiAdapter: wiki)
        patentLoopEngine = engine
        return engine
    }
}

// MARK: - Message Bubble

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
