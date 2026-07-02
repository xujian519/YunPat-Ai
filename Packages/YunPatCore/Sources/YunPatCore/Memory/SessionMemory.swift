import Foundation
import YunPatNetworking

/// 轻量会话记忆 — 跟踪当前标签页的对话历史，与 MemoryEngine 的五层记忆互补
public struct SessionMemory: Sendable {
    public private(set) var messages: [Message] = []
    public let tabId: UUID

    public init(tabId: UUID = UUID()) {
        self.tabId = tabId
    }

    public mutating func append(_ msg: Message) {
        messages.append(msg)
    }

    /// 为下一次 LLM 调用构建消息历史
    /// - Parameters:
    ///   - systemPrompt: 系统提示词（放在最前面）
    ///   - maxMessages: 最多保留的消息数
    ///   - currentRequest: 当前用户请求（追加在末尾）
    /// - Returns: 按 system → history → currentRequest 排列的消息列表
    public func buildHistory(
        systemPrompt: String,
        maxMessages: Int = 50,
        currentRequest: Message? = nil
    ) -> [Message] {
        var result: [Message] = [Message(role: .system, content: systemPrompt)]
        let recent = Array(messages.suffix(maxMessages))
        result.append(contentsOf: recent)
        if let req = currentRequest {
            result.append(req)
        }
        return result
    }
}
