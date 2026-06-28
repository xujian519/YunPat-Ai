import SwiftUI
import YunPatCore
import YunPatNetworking

struct ChatTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var loopState: LoopState
    var loopPreference: AgentFlow
    var loopModel: String
    var sessionMemory: SessionMemory

    /// todo 清单（markdown checklist，由 Agent 通过 todo 工具设置）
    var todoChecklist: String = ""
    /// 待处理的 clarify 询问（nil = 无待处理）
    var clarifyRequest: ClarifyRequest? = nil

    init(title: String = "新对话", flow: AgentFlow = .copilot) {
        let tabId = UUID()
        self.id = tabId
        self.title = title
        self.messages = []
        self.loopState = .idle
        self.loopPreference = flow
        self.loopModel = ModelProvider.deepseek.defaultModel
        self.sessionMemory = SessionMemory(tabId: tabId)
    }

    var flowLabel: String {
        switch loopPreference {
        case .copilot: return "Copilot"
        case .guided: return "Guided"
        case .fullAgent: return "FullAgent"
        }
    }

    var flowIcon: String {
        switch loopPreference {
        case .copilot: return "circle"
        case .guided: return "circle.dotted"
        case .fullAgent: return "circle.circle"
        }
    }

    static func == (lhs: ChatTab, rhs: ChatTab) -> Bool { lhs.id == rhs.id }
}

extension ChatTab {
    var loopStateDescription: String {
        loopState.description
    }
}

/// Clarify 请求（从 Core 映射到 App 层使用）
struct ClarifyRequestDisplay: Identifiable, Sendable {
    let id: UUID
    let question: String
    let options: [String]
    let allowMultiple: Bool
    var answer: String? = nil

    init(question: String, options: [String] = [], allowMultiple: Bool = false) {
        self.id = UUID()
        self.question = question
        self.options = options
        self.allowMultiple = allowMultiple
    }

    init(from request: YunPatCore.ClarifyRequest) {
        self.id = UUID()
        self.question = request.question
        self.options = request.options
        self.allowMultiple = request.allowMultiple
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Message.Role
    var content: String
    let timestamp: Date

    init(role: Message.Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool { lhs.id == rhs.id }
}
