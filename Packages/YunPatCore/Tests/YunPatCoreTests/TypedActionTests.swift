import XCTest
@testable import YunPatCore

final class TypedActionTests: XCTestCase {
    func testDispatch_handlerCalled() async {
        let d = ActionDispatcher()
        let e = XCTestExpectation(description: "handler called")
        await d.on(NewTabAction.self) { _ in e.fulfill() }
        await d.dispatch(NewTabAction())
        await fulfillment(of: [e], timeout: 1)
    }
}
