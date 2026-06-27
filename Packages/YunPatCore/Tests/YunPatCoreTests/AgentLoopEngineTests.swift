import XCTest
import YunPatNetworking
@testable import YunPatCore

final class AgentLoopEngineTests: XCTestCase {
    func testRun_copilotMode_returnsCompletedEvenOnError() async throws {
        let router = ModelRouter()
        let provider = OpenAIProvider(apiKey: "test-key")
        await router.register(provider)
        let engine = AgentLoopEngine(modelRouter: router, provider: .openai)
        let result = try await engine.run(request: UserRequest(content: "Hello"), flow: .copilot)
        switch result {
        case .completed(let text):
            XCTAssertTrue(text.contains("Error"), "Should get error with test API key")
        default:
            XCTFail("Expected .completed")
        }
    }

    func testRun_returnsIdleAfterCompletion() async throws {
        let router = ModelRouter()
        let provider = OpenAIProvider(apiKey: "test-key")
        await router.register(provider)
        let engine = AgentLoopEngine(modelRouter: router, provider: .openai)
        _ = try await engine.run(request: UserRequest(content: "test"), flow: .copilot)
        let state = await engine.state
        guard case .idle = state else { XCTFail("Expected .idle"); return }
    }
}
