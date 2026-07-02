import XCTest

@testable import YunPatCore

final class FactBlackboardTests: XCTestCase {
    func testWriteAndReadFacts() {
        let board = FactBlackboard()
        board.writeFacts(
            technicalField: "机械",
            problem: "传动效率低",
            inventionPoints: ["螺旋机构"]
        )
        XCTAssertEqual(board.technicalField, "机械")
        XCTAssertEqual(board.inventionPoints.count, 1)
    }

    func testLockFacts() {
        let board = FactBlackboard()
        board.lockFacts()
        XCTAssertTrue(board.isFactsLocked)
    }

    func testToStructuredFacts() {
        let board = FactBlackboard()
        board.writeFacts(
            technicalField: "电学",
            problem: "功耗高",
            inventionPoints: ["低功耗电路"]
        )
        let facts = board.toStructuredFacts()
        XCTAssertEqual(facts.technicalField, "电学")
    }
}
