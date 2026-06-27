import XCTest
@testable import YunPatNetworking

final class DeepSeekProviderTests: XCTestCase {
    func testChat_withoutAPIKey_throwsError() async {
        let provider = OpenAICompatProvider(apiKey: "", baseURL: URL(string: "https://api.deepseek.com/v1")!, provider: .deepseek)
        let request = ChatRequest(model: "deepseek-chat", messages: [Message(role: .user, content: "Hello")])
        var caughtError: Error?
        do { for try await _ in provider.chat(request) { } } catch { caughtError = error }
        XCTAssertNotNil(caughtError)
    }

    func testGLMProvider_initializesCorrectly() {
        let provider = OpenAICompatProvider(apiKey: "test", baseURL: URL(string: "https://open.bigmodel.cn/api/paas/v4")!, provider: .glm)
        XCTAssertEqual(provider.provider, .glm)
    }
}
