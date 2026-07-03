import XCTest

@testable import YunPatCore

final class LegalStateMachineTests: XCTestCase {
    func testValidTransition() async {
        let stateMachine: LegalStateMachine = LegalStateMachine()
        let result: TransitionResult = await stateMachine.transition(to: .factFinding)
        guard case .success = result else {
            XCTFail("预期成功转换到 factFinding")
            return
        }
        let state = await stateMachine.currentState
        XCTAssertEqual(state, .factFinding)
    }

    func testInvalidTransition() async {
        let stateMachine: LegalStateMachine = LegalStateMachine()
        let result: TransitionResult = await stateMachine.transition(to: .executing)
        guard case .failure = result else {
            XCTFail("应拒绝从 idle 到 executing")
            return
        }
    }

    func testRollback() async {
        let stateMachine: LegalStateMachine = LegalStateMachine()
        _ = await stateMachine.transition(to: .factFinding)
        _ = await stateMachine.transition(to: .legalBasis)
        let result: TransitionResult = await stateMachine.rollback(to: .factFinding, reason: "新事实")
        guard case .success = result else {
            XCTFail("预期回滚成功")
            return
        }
        let state = await stateMachine.currentState
        XCTAssertEqual(state, .factFinding)
    }
}
