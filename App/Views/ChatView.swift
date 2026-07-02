import SwiftUI
import YunPatCore
import YunPatNetworking

@MainActor
final class ChatManager: ObservableObject {
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var clarifying: Bool = false

    private let modelRouter: ModelRouter
    private let loopEngine: AgentLoopEngine
    private var patentLoopEngine: PatentLoopEngine?
    private let requestQueue: GlobalRequestQueue

    /// 待处理的 clarify 请求（由 sendMessage 后的结果触发）
    private var pendingClarify: ClarifyRequestDisplay?

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
                    let idx = tabManager.tabs.firstIndex(where: { $0.id == activeID })
                else { return }
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
            !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let tab: Tab = tabManager.tabs[idx]
        let userMessage: ChatMessage = ChatMessage(role: .user, content: inputText)
        tabManager.appendMessage(to: activeID, userMessage)
        tabManager.tabs[idx].sessionMemory.append(Message(role: .user, content: inputText))
        let sentText: String = inputText
        inputText = ""
        isStreaming = true
        clarifying = false
        tabManager.tabs[idx].loopState = .running(step: "init")

        // 插入占位 assistant 消息供流式填充
        let placeholder: ChatMessage = ChatMessage(role: .assistant, content: "")
        tabManager.appendMessage(to: activeID, placeholder)
        let capturedTabID: UUID = activeID

        // 流式回调：每收到文本增量，更新最后一条消息
        let onChunk: PatentLoopHooks.OnStreamChunk = { [tabManager] text in
            Task { @MainActor in
                guard let idx = tabManager.tabs.firstIndex(where: { $0.id == capturedTabID }),
                    let lastIdx = tabManager.tabs[idx].messages.indices.last
                else { return }
                tabManager.tabs[idx].messages[lastIdx].content += text
            }
        }

        do {
            try await executeFlow(
                tab: tab, idx: idx, sentText: sentText,
                onChunk: onChunk, tabManager: tabManager
            )
        } catch {
            await handleSendError(
                error: error, capturedTabID: capturedTabID, tabManager: tabManager
            )
        }
        isStreaming = false
    }

    private func handleLoopResult(
        _ result: LoopResult, activeID: UUID,
        in tabManager: TabManager, streamed: Bool = false
    ) async {
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
            let msg: String = issues.map(\.description).joined(separator: "\n")
            tabManager.appendMessage(to: activeID, ChatMessage(role: .assistant, content: "需修正：\n\(msg)"))
        case .exceededRevisionLimit(let issues):
            let msg: String = issues.map(\.description).joined(separator: "\n")
            tabManager.appendMessage(to: activeID, ChatMessage(role: .assistant, content: "超过修订次数限制：\n\(msg)"))
        case .cancelled:
            tabManager.appendMessage(to: activeID, ChatMessage(role: .assistant, content: "已取消"))
        }
    }

    private func executeFlow(
        tab: Tab, idx: Int, sentText: String,
        onChunk: @escaping PatentLoopHooks.OnStreamChunk,
        tabManager: TabManager
    ) async throws {
        let flow: AgentFlow = tab.loopPreference
        let model: String = tab.loopModel
        switch flow {
        case .copilot, .guided:
            let history: [Message] = tabManager.tabs[idx].sessionMemory.messages
            let result: LoopResult = try await loopEngine.run(
                request: UserRequest(content: sentText),
                flow: flow,
                model: model,
                history: history,
                onStreamChunk: onChunk
            )
            tabManager.tabs[idx].loopState = .idle
            if case .completed(let text) = result {
                tabManager.tabs[idx].sessionMemory.append(Message(role: .assistant, content: text))
            }
            await handleLoopResult(result, activeID: activeID, in: tabManager, streamed: true)
        case .fullAgent:
            let history: [Message] = tabManager.tabs[idx].sessionMemory.messages
            let result: LoopResult = try await getPatentLoopEngine().run(
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
    }

    private func handleSendError(error: Error, capturedTabID: UUID, tabManager: TabManager) async {
        guard let idx = tabManager.tabs.firstIndex(where: { $0.id == capturedTabID }),
            let lastIdx = tabManager.tabs[idx].messages.indices.last
        else { return }
        tabManager.tabs[idx].loopState = .idle
        let existing: String = tabManager.tabs[idx].messages[lastIdx].content
        tabManager.tabs[idx].messages[lastIdx].content =
            existing.isEmpty
            ? "Error: \(error.localizedDescription)"
            : existing + "\n\nError: \(error.localizedDescription)"
    }

    /// 用户对 clarify 做出回答后，将回答作为新消息发送
    func answerClarify(_ answer: String, in tabManager: TabManager) async {
        guard let activeID = tabManager.activeTabID,
            let idx = tabManager.tabs.firstIndex(where: { $0.id == activeID })
        else { return }
        clarifying = false
        pendingClarify = nil
        tabManager.tabs[idx].clarifyRequest = nil

        let userMessage: ChatMessage = ChatMessage(role: .user, content: answer)
        tabManager.appendMessage(to: activeID, userMessage)
        isStreaming = true
        tabManager.tabs[idx].loopState = .running(step: "executing")

        do {
            let flow: AgentFlow = tabManager.tabs[idx].loopPreference
            let model: String = tabManager.tabs[idx].loopModel
            let result: LoopResult = try await loopEngine.run(
                request: UserRequest(content: answer),
                flow: flow,
                model: model,
                onStreamChunk: nil
            )
            tabManager.tabs[idx].loopState = .idle
            await handleLoopResult(result, activeID: activeID, in: tabManager)
        } catch {
            tabManager.tabs[idx].loopState = .idle
            let errorMessage: String = "Error: \(error.localizedDescription)"
            tabManager.appendMessage(to: activeID, ChatMessage(role: .assistant, content: errorMessage))
        }
        isStreaming = false
    }

    /// 取消 clarify
    func dismissClarify(in tabManager: TabManager) {
        guard let activeID = tabManager.activeTabID,
            let idx = tabManager.tabs.firstIndex(where: { $0.id == activeID })
        else { return }
        clarifying = false
        pendingClarify = nil
        tabManager.tabs[idx].clarifyRequest = nil
    }

    /// 为当前 tab 设置 Agent Flow 模式
    func setFlow(_ flow: AgentFlow, in tabManager: TabManager) {
        guard let activeID = tabManager.activeTabID,
            let idx = tabManager.tabs.firstIndex(where: { $0.id == activeID })
        else { return }
        tabManager.tabs[idx].loopPreference = flow
    }

    /// 为当前 tab 设置模型
    func setModel(_ model: String, in tabManager: TabManager) {
        guard let activeID = tabManager.activeTabID,
            let idx = tabManager.tabs.firstIndex(where: { $0.id == activeID })
        else { return }
        tabManager.tabs[idx].loopModel = model
    }

    // MARK: - Patent Engine

    private func getPatentLoopEngine() -> PatentLoopEngine {
        if let existing = patentLoopEngine {
            return existing
        }
        let vaultPath: String = UserDefaults.standard.string(forKey: "yunpat.vaultPath") ?? ""
        let wiki: WikiAdapter = WikiAdapter(vaultPath: URL(filePath: vaultPath))
        let engine: PatentLoopEngine = PatentLoopEngine(modelRouter: modelRouter, wikiAdapter: wiki)
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
