import XCTest
@testable import YunPatCore

final class ChecklistEngineTests: XCTestCase {
    func testLoadDraftingConstraints() async {
        let e = ChecklistEngine()
        let c = await e.loadConstraints(for: "drafting")
        XCTAssertEqual(c.count, 6)
        XCTAssertEqual(c.first?.articleId, "A22.2")
    }

    func testSummary() async {
        let e = ChecklistEngine()
        let r = [
            CheckResult(
                constraintId: "A22.2",
                passed: true,
                severity: .info,
                message: "ok"
            ),
            CheckResult(
                constraintId: "A22.3",
                passed: false,
                severity: .error,
                message: "缺乏创造性"
            ),
        ]
        let s = await e.summary(r)
        XCTAssertTrue(s.contains("通过: 1"))
    }
}
