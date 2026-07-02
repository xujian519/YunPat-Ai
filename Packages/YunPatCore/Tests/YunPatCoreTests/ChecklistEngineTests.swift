import XCTest

@testable import YunPatCore

final class ChecklistEngineTests: XCTestCase {
    func testLoadDraftingConstraints() async {
        let engine: ChecklistEngine = ChecklistEngine()
        let constraints: [CheckConstraint] = await engine.loadConstraints(for: "drafting")
        XCTAssertEqual(constraints.count, 6)
        XCTAssertEqual(constraints.first?.articleId, "A22.2")
    }

    func testSummary() async {
        let engine: ChecklistEngine = ChecklistEngine()
        let results: [CheckResult] = [
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
            )
        ]
        let summaryText: String = await engine.summary(results)
        XCTAssertTrue(summaryText.contains("通过: 1"))
    }
}
