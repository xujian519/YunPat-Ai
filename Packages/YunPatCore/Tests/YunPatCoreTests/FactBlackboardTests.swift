import XCTest

@testable import YunPatCore

final class FactBlackboardTests: XCTestCase {
    func testWriteAndReadFacts() async {
        let board = FactBlackboard()
        await board.writeFacts(
            technicalField: "机械",
            problem: "传动效率低",
            inventionPoints: ["螺旋机构"]
        )
        let techField = await board.technicalField
        let invPoints = await board.inventionPoints
        XCTAssertEqual(techField, "机械")
        XCTAssertEqual(invPoints.count, 1)
    }

    func testLockFacts() async {
        let board = FactBlackboard()
        await board.lockFacts()
        let locked = await board.isFactsLocked
        XCTAssertTrue(locked)
    }

    func testToStructuredFacts() async {
        let board = FactBlackboard()
        await board.writeFacts(
            technicalField: "电学",
            problem: "功耗高",
            inventionPoints: ["低功耗电路"]
        )
        let facts = await board.toStructuredFacts()
        XCTAssertEqual(facts.technicalField, "电学")
    }
}
