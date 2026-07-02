import XCTest

@testable import YunPatNetworking

final class AnthropicProviderTests: XCTestCase {
    func testChat_withoutAPIKey_throwsError() async {
        let provider = AnthropicProvider(apiKey: "")
        let request = ChatRequest(model: "claude-sonnet-4-20250514", messages: [Message(role: .user, content: "Hello")])
        var caughtError: Error?
        do { for try await _ in provider.chat(request) {} } catch { caughtError = error }
        XCTAssertNotNil(caughtError)
    }

    func testCapabilities_returnsAnthropicCaps() {
        let provider = AnthropicProvider(apiKey: "test-key")
        let caps = provider.capabilities()
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertEqual(caps.maxContextTokens, 200_000)
    }
}
