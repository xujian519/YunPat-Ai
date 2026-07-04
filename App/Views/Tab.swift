import SwiftUI // swiftlint:disable:this file_name
import YunPatCore
import YunPatNetworking

enum TabType: String, CaseIterable, Sendable {
    case patent  // 案件专用标签
    case general  // 通用对话标签
}

struct ChatTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var type: TabType
    var messages: [ChatMessage]
    var loopState: LoopState
    var loopPreference: AgentFlow
    var autoFlowEnabled: Bool
    var loopModel: String
    var sessionMemory: SessionMemory
    var caseId: String?  // 案件编号（patent 类型）
    var workspacePath: URL?  // 工作目录

    /// todo 清单（markdown checklist，由 Agent 通过 todo 工具设置）
    var todoChecklist: String = ""
    /// 待处理的 clarify 询问（nil = 无待处理）
    var clarifyRequest: ClarifyRequest?

    init(title: String = "新对话", type: TabType = .general, flow: AgentFlow = .copilot) {
        let tabId = UUID()
        self.id = tabId
        self.title = title
        self.type = type
        self.messages = []
        self.loopState = .idle
        self.loopPreference = flow
        self.autoFlowEnabled = (type == .general)
        self.loopModel = "deepseek-v4-flash"
        self.sessionMemory = SessionMemory(tabId: tabId)
    }

    /// 根据用户请求内容解析实际 Flow（autoFlow 开启时自动分类）
    func resolvedFlow(for userMessage: String) -> AgentFlow {
        if autoFlowEnabled {
            return FlowClassifier().classify(userMessage)
        }
        return loopPreference
    }

    var flowLabel: String {
        switch loopPreference {
        case .copilot: return "自由问答"
        case .guided: return "分步撰写"
        case .fullAgent: return "自动代理"
        }
    }

    var flowIcon: String {
        switch loopPreference {
        case .copilot: return "circle"
        case .guided: return "circle.dotted"
        case .fullAgent: return "circle.circle"
        }
    }

    var typeIcon: String {
        switch type {
        case .patent: return "doc.text.magnifyingglass"
        case .general: return "bubble.left"
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
    var answer: String?

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
