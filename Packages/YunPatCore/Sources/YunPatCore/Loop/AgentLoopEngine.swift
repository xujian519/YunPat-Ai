import Foundation
import YunPatNetworking

public actor AgentLoopEngine: LoopEngine {
    public var state: LoopState = .idle

    public init() {}

    public func run(request: UserRequest, flow: AgentFlow) async throws -> LoopResult {
        state = .running(step: "executing")
        let response = "收到：\u{300c}\(request.content)\u{300d}"
        state = .idle
        return .completed(response)
    }
}
