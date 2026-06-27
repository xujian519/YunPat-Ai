import XCTest
@testable import YunPatCore

final class AgentLoopEngineTests: XCTestCase {
    func testRun_copilotMode_returnsCompleted() async throws {
        let engine = AgentLoopEngine()
        let result = try await engine.run(request: UserRequest(content: "Hello"), flow: .copilot)
        guard case .completed = result else { XCTFail("Expected .completed"); return }
    }

    func testRun_returnsIdleAfterCompletion() async throws {
        let engine = AgentLoopEngine()
        _ = try await engine.run(request: UserRequest(content: "test"), flow: .copilot)
        let state = await engine.state
        guard case .idle = state else { XCTFail("Expected .idle"); return }
    }
}
