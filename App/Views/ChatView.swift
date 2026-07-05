import SwiftUI
import UserNotifications
import YunPatCore
import YunPatNetworking

@MainActor
final class ChatManager: ObservableObject { // swiftlint:disable:this type_body_length
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var clarifying: Bool = false
    @Published var pendingDocumentQuestions: [String] = []
    @Published var pendingDocumentAnnotations: [DocumentAnnotation] = []

    private let modelRouter: ModelRouter
    private let loopEngine: AgentLoopEngine
    private var patentLoopEngine: PatentLoopEngine?
    private let requestQueue: GlobalRequestQueue

    /// 待处理的 clarify 请求（由 sendMessage 后的结果触发）
    private var pendingClarify: ClarifyRequestDisplay?

    nonisolated(unsafe) private var docObserver: NSObjectProtocol?

    init(modelRouter: ModelRouter, requestQueue: GlobalRequestQueue? = nil) {
        self.modelRouter = modelRouter
        self.loopEngine = AgentLoopEngine(modelRouter: modelRouter)
        self.requestQueue = requestQueue ?? GlobalRequestQueue()
        requestNotificationPermission()

        docObserver = NotificationCenter.default.addObserver(
            forName: .documentChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let change = note.object as? DocumentChangeNotification else { return }
            MainActor.assumeIsolated { self.handleDocumentChange(change) }
        }
    }

    deinit {
        if let docObserver { NotificationCenter.default.removeObserver(docObserver) }
    }

    private func handleDocumentChange(_ change: DocumentChangeNotification) {
        let questions: [String] = change.annotations
            .filter { $0.type == .question }
            .map { "[L\($0.line)] \($0.content)" }
        if !questions.isEmpty {
            pendingDocumentQuestions = questions
        }
        pendingDocumentAnnotations = change.annotations
        if !change.annotations.isEmpty {
            objectWillChange.send()
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendCollaborationNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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

        let tab: ChatTab = tabManager.tabs[idx]
        var augmentedInput: String = inputText

        if !pendingDocumentQuestions.isEmpty {
            let docContext: String = pendingDocumentQuestions
                .map { "- 文档疑问: \($0)" }
                .joined(separator: "\n")
            augmentedInput = "【文档标注问题】\n\(docContext)\n\n---\n\n\(inputText)"
            pendingDocumentQuestions = []
        }

        let userMessage: ChatMessage = ChatMessage(role: .user, content: augmentedInput)
        tabManager.appendMessage(to: activeID, userMessage)
        tabManager.tabs[idx].sessionMemory.append(Message(role: .user, content: augmentedInput))
        let sentText: String = augmentedInput
        inputText = ""
        isStreaming = true
        clarifying = false
        tabManager.tabs[idx].loopState = .running(step: "init")

        // 插入占位 assistant 消息供流式填充
        let placeholder: ChatMessage = ChatMessage(role: .assistant, content: "")
        tabManager.appendMessage(to: activeID, placeholder)
        let capturedTabID: UUID = activeID

        // 流式回调：每收到文本增量，更新最后一条消息
        let onChunk: PatentLoopHooks.OnStreamChunk = { [weak tabManager] text in
            Task { @MainActor [weak tabManager] in
                guard let tabManager, let idx = tabManager.tabs.firstIndex(where: { $0.id == capturedTabID }),
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
                sendCollaborationNotification(
                    title: "YunPat-Ai 需要确认",
                    body: first
                )
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
        tab: ChatTab, idx: Int, sentText: String,
        onChunk: @escaping PatentLoopHooks.OnStreamChunk,
        tabManager: TabManager
    ) async throws {
        let flow: AgentFlow = tab.resolvedFlow(for: sentText)
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
            await handleLoopResult(result, activeID: tab.id, in: tabManager, streamed: true)
        case .fullAgent:
            let history: [Message] = tabManager.tabs[idx].sessionMemory.messages
            let engine: PatentLoopEngine = await getPatentLoopEngine()
            let result: LoopResult = try await engine.run(
                request: UserRequest(content: sentText),
                flow: .fullAgent,
                history: history,
                onStreamChunk: onChunk
            )
            tabManager.tabs[idx].loopState = .idle
            if case .completed(let text) = result {
                tabManager.tabs[idx].sessionMemory.append(Message(role: .assistant, content: text))
            }
            await handleLoopResult(result, activeID: tab.id, in: tabManager, streamed: true)
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

    /// 将文档标注中的问题作为消息发送给 Agent
    func sendDocumentAnnotations(in tabManager: TabManager) async {
        guard tabManager.activeTabID != nil else { return }

        let questions: [String] = pendingDocumentQuestions
        let annotations: [DocumentAnnotation] = pendingDocumentAnnotations
        guard !questions.isEmpty || !annotations.isEmpty else { return }

        var parts: [String] = []
        if !questions.isEmpty {
            parts.append("【文档标注中的问题】\n" + questions.joined(separator: "\n"))
        }
        if !annotations.isEmpty {
            let summary: String = annotations.map {
                switch $0.type {
                case .question: return "[L\($0.line)] 问题: \($0.content)"
                case .deletion: return "[L\($0.line)] 删除标记: \($0.content)"
                case .insertion: return "[L\($0.line)] 插入标记: \($0.content)"
                case .comment: return "[L\($0.line)] 备注: \($0.content)"
                }
            }.joined(separator: "\n")
            parts.append("【标注摘要】\n" + summary)
        }

        let docContext: String = parts.joined(separator: "\n\n")
        inputText = docContext
        pendingDocumentQuestions = []
        pendingDocumentAnnotations = []

        await sendMessage(in: tabManager)
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

    private func getPatentLoopEngine() async -> PatentLoopEngine {
        if let existing = patentLoopEngine {
            return existing
        }
        let wiki: WikiAdapter = await KnowledgeBaseManager.shared.wikiAdapter
            ?? WikiAdapter(vaultPath: URL(filePath: ""))
        let engine: PatentLoopEngine = PatentLoopEngine(modelRouter: modelRouter, wikiAdapter: wiki)
        patentLoopEngine = engine
        return engine
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    var isStreaming: Bool = false

    @State private var typingDotScale: CGFloat = 1.0

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            if message.role == .user { Spacer() }

            if message.role == .assistant {
                avatarView
                    .padding(.top, Spacing.xxs)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.xxs) {
                Text(message.content.isEmpty && isStreaming ? " " : message.content)
                    .font(FontStyle.body)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(message.role == .user ? Color.appBubbleUser : Color.appBubbleAssistant)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .stroke(
                                message.role == .user
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.appSeparator.opacity(0.4),
                                lineWidth: 0.5
                            )
                    )
                    .foregroundStyle(message.role == .user ? Color.appBubbleUserText : Color.appTextPrimary)
                    .textSelection(.enabled)
                    .animation(.interactiveSpring(duration: AnimationDuration.fast), value: message.content)
                    .accessibilityLabel(buildAccessibilityLabel())
                    .accessibilityAddTraits(.isStaticText)
                    .contextMenu {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .keyboardShortcut("c", modifiers: .command)
                    }

                if !message.content.isEmpty && !isStreaming {
                    Text(message.timestamp, style: .time)
                        .font(FontStyle.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, Spacing.xxs)
                }

                if isStreaming && message.role == .assistant {
                    typingIndicator
                        .padding(.leading, Spacing.sm)
                        .padding(.top, 2)
                }
            }

            if message.role == .user {
                avatarView
                    .padding(.top, Spacing.xxs)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 2)
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(message.role == .user ? Color.appBubbleUser : Color.appSurfaceSecondary)
                .frame(width: IconSize.avatar, height: IconSize.avatar)

            Image(systemName: message.role == .user ? "person.fill" : "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(message.role == .user ? Color.appBubbleUserText : .secondary)
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.accentColor.opacity(0.6 - Double(index) * 0.15))
                    .frame(width: 5, height: 5)
                    .scaleEffect(typingDotScale)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: typingDotScale
                    )
            }
        }
        .onAppear { startTypingAnimation() }
        .accessibilityLabel("助手正在输入")
    }

    private func buildAccessibilityLabel() -> String {
        let role: String = message.role == .user ? "用户" : "助手"
        let content: String = message.content.isEmpty ? "输入中" : message.content
        return "\(role): \(content)"
    }

    private func startTypingAnimation() {
        withAnimation {
            typingDotScale = 0.4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation {
                typingDotScale = 1.0
            }
        }
    }
}
