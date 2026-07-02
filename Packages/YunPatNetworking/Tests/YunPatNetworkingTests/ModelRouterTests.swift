import XCTest

@testable import YunPatNetworking

final class ModelRouterTests: XCTestCase {
    func testRegisterAndRoute_returnsCorrectProvider() async {
        let router = ModelRouter()
        let openAIProvider = OpenAIProvider(apiKey: "test-key")
        await router.register(openAIProvider)
        let result: (any ModelBackend)? = await router.route(provider: .openai)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.provider, .openai)
    }

    func testRoute_toUnregisteredProvider_returnsNil() async {
        let router = ModelRouter()
        let result: (any ModelBackend)? = await router.route(provider: .openai)
        XCTAssertNil(result)
    }
}
