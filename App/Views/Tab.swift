import SwiftUI
import YunPatCore
import YunPatNetworking

struct ChatTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var loopState: LoopState

    init(title: String = "新对话") {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.loopState = .idle
    }

    static func == (lhs: ChatTab, rhs: ChatTab) -> Bool { lhs.id == rhs.id }
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Message.Role
    let content: String
    let timestamp: Date

    init(role: Message.Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool { lhs.id == rhs.id }
}
