import XCTest
@testable import YunPatCore

final class ContextEngineTests: XCTestCase {
    func testBuildPrompt_copilotMode_injectsBasicContext() async throws {
        let engine = ContextEngine()
        let prompt = try await engine.buildPrompt(for: UserRequest(content: "你好"), flow: .copilot)
        XCTAssertFalse(prompt.isEmpty)
        XCTAssertTrue(prompt.contains("你好"))
    }

    func testBuildPrompt_respectsTokenBudget() async throws {
        let engine = ContextEngine()
        let prompt = try await engine.buildPrompt(for: UserRequest(content: "你好"), flow: .copilot, maxTokenBudget: 100)
        XCTAssertLessThanOrEqual(prompt.count, 500)
    }
}
