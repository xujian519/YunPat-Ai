import XCTest
@testable import YunPatCore

final class LegalStateMachineTests: XCTestCase {
    func testValidTransition() {
        let sm = LegalStateMachine()
        let r = sm.transition(to: .factFinding)
        guard case .success = r else { XCTFail(); return }
        XCTAssertEqual(sm.currentState, .factFinding)
    }

    func testInvalidTransition() {
        let sm = LegalStateMachine()
        let r = sm.transition(to: .executing)
        guard case .failure = r else { XCTFail("应拒绝"); return }
    }

    func testRollback() {
        let sm = LegalStateMachine()
        _ = sm.transition(to: .factFinding)
        _ = sm.transition(to: .legalBasis)
        let r = sm.rollback(to: .factFinding, reason: "新事实")
        guard case .success = r else { XCTFail(); return }
        XCTAssertEqual(sm.currentState, .factFinding)
    }
}
