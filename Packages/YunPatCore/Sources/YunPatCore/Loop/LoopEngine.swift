import Foundation

public struct UserRequest: Sendable {
    public let content: String
    public let attachments: [URL]
    public init(content: String, attachments: [URL] = []) {
        self.content = content; self.attachments = attachments
    }
}

public protocol LoopEngine: Sendable {
    func run(request: UserRequest, flow: AgentFlow) async throws -> LoopResult
    var state: LoopState { get async }
}
