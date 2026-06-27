import Foundation
import YunPatNetworking

public actor AgentLoopEngine: LoopEngine {
    public var state: LoopState = .idle
    private let modelRouter: ModelRouter
    private let provider: ModelProvider
    private let contextEngine: ContextEngine

    public init(modelRouter: ModelRouter, provider: ModelProvider = .deepseek) {
        self.modelRouter = modelRouter
        self.provider = provider
        self.contextEngine = ContextEngine()
    }

    public func run(request: UserRequest, flow: AgentFlow) async throws -> LoopResult {
        state = .running(step: "building-context")
        let systemPrompt = try await contextEngine.buildPrompt(for: request, flow: flow)
        state = .running(step: "executing")

        let messages: [Message] = [Message(role: .user, content: request.content)]
        let chatRequest = ChatRequest(model: "deepseek-chat", messages: messages, systemPrompt: systemPrompt)

        do {
            let stream = try await modelRouter.chat(chatRequest, provider: provider)
            var fullResponse = ""
            for try await chunk in stream {
                switch chunk {
                case .text(let text): fullResponse += text
                case .finish: break
                case .error(let error):
                    state = .idle
                    return .completed("Error: \(error.localizedDescription)")
                default: break
                }
            }
            state = .idle
            return .completed(fullResponse)
        } catch {
            state = .idle
            return .completed("Error: \(error.localizedDescription)")
        }
    }
}
