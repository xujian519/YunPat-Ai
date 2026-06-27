import XCTest
@testable import YunPatNetworking

final class OpenAIProviderTests: XCTestCase {
    func testChat_withoutAPIKey_throwsError() async {
        let provider = OpenAIProvider(apiKey: "")
        let request = ChatRequest(model: "gpt-4o", messages: [Message(role: .user, content: "Hello")])
        var caughtError: Error?
        do { for try await _ in provider.chat(request) { } } catch { caughtError = error }
        XCTAssertNotNil(caughtError, "Expected error when API key is empty")
    }

    func testCapabilities_returnsOpenAICaps() {
        let provider = OpenAIProvider(apiKey: "test-key")
        let caps = provider.capabilities()
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertTrue(caps.supportsToolCalling)
    }
}
