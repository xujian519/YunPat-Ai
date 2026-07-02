import XCTest

@testable import YunPatCore

final class LegalStateMachineTests: XCTestCase {
    func testValidTransition() {
        let stateMachine: LegalStateMachine = LegalStateMachine()
        let result: TransitionResult = stateMachine.transition(to: .factFinding)
        guard case .success = result else {
            XCTFail("预期成功转换到 factFinding")
            return
        }
        XCTAssertEqual(stateMachine.currentState, .factFinding)
    }

    func testInvalidTransition() {
        let stateMachine: LegalStateMachine = LegalStateMachine()
        let result: TransitionResult = stateMachine.transition(to: .executing)
        guard case .failure = result else {
            XCTFail("应拒绝从 idle 到 executing")
            return
        }
    }

    func testRollback() {
        let stateMachine: LegalStateMachine = LegalStateMachine()
        _ = stateMachine.transition(to: .factFinding)
        _ = stateMachine.transition(to: .legalBasis)
        let result: TransitionResult = stateMachine.rollback(to: .factFinding, reason: "新事实")
        guard case .success = result else {
            XCTFail("预期回滚成功")
            return
        }
        XCTAssertEqual(stateMachine.currentState, .factFinding)
    }
}
