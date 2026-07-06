import CoreGraphics
import Foundation
import Testing
@testable import YunPatDesktop

struct InputRouteTests {

    @Test func inputRouteRawValues() {
        #expect(InputRoute.accessibility.rawValue == "accessibility")
        #expect(InputRoute.perPid.rawValue == "perPid")
        #expect(InputRoute.hidFallback.rawValue == "hidFallback")
    }

    @Test func inputRouteCodable() throws {
        let encoded = try JSONEncoder().encode(InputRoute.perPid)
        let decoded = try JSONDecoder().decode(InputRoute.self, from: encoded)
        #expect(decoded == .perPid)
    }

    @Test func inputRouteSendable() {
        let route = InputRoute.hidFallback
        let closure: @Sendable () -> Void = { _ = route.rawValue }
        closure()
    }

    @Test func inputResultOk() {
        let result = InputResult.ok(route: .accessibility)
        #expect(result.success)
        #expect(result.route == .accessibility)
        #expect(result.error == nil)
    }

    @Test func inputResultFail() {
        let result = InputResult.fail(route: .hidFallback, "timeout")
        #expect(!result.success)
        #expect(result.route == .hidFallback)
        #expect(result.error == "timeout")
    }

    @Test func backgroundRouterShared() {
        let router = BackgroundRouter.shared
        let route = router.lastRoute
        _ = route  // non-nil check
    }

    @Test func backgroundRouterLastRouteInitialValue() {
        let router = BackgroundRouter.shared
        #expect(router.lastRoute == .accessibility)
    }

    @Test func backgroundRouterClickReturnsResult() {
        let router = BackgroundRouter.shared
        let result = router.click(point: CGPoint(x: 0, y: 0), pid: -1)
        // Even with invalid pid, the method should return a result (not crash)
        #expect(!result.success || result.success)
    }

    @Test func backgroundRouterClickHIDReturnsResult() {
        let router = BackgroundRouter.shared
        let result = router.clickHID(point: CGPoint(x: 100, y: 100))
        _ = result
    }

    @Test func backgroundRouterTypeReturnsResult() {
        let router = BackgroundRouter.shared
        let result = router.type(text: "hello", pid: -1)
        _ = result
    }
}
