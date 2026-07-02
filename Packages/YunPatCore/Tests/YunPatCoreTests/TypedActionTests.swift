import XCTest

@testable import YunPatCore

final class TypedActionTests: XCTestCase {
    func testDispatch_handlerCalled() async {
        let dispatcher = ActionDispatcher()
        let expectation = XCTestExpectation(description: "handler called")
        await dispatcher.on(NewTabAction.self) { _ in expectation.fulfill() }
        await dispatcher.dispatch(NewTabAction())
        await fulfillment(of: [expectation], timeout: 1)
    }
}
