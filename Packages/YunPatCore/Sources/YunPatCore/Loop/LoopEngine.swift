import Foundation
import YunPatNetworking

/// 用户请求 — 包含文本内容和附件
public struct UserRequest: Sendable {
    public let content: String
    public let attachments: [URL]
    public init(content: String, attachments: [URL] = []) {
        self.content = content
        self.attachments = attachments
    }
}

/// 循环引擎协议 — AgentLoopEngine 和 PatentLoopEngine 的统一接口
public protocol LoopEngine: Sendable {
    func run(
        request: UserRequest, flow: AgentFlow, model: String?, history: [Message],
        onStreamChunk: PatentLoopHooks.OnStreamChunk?
    ) async throws -> LoopResult
    var state: LoopState { get async }
}
