import XCTest

@testable import YunPatCore

final class PatentRubricTests: XCTestCase {
    func testDrafting_has8Criteria() { XCTAssertEqual(PatentRubric.drafting.criteria.count, 8) }
    func testAll5_returnsPass() {
        var rubric: PatentRubric = PatentRubric.drafting
        for idx in rubric.criteria.indices { rubric.criteria[idx].score = 5 }
        guard case .pass = rubric.verdict else {
            XCTFail("Expected pass verdict")
            return
        }
    }
    func testOneAt2_returnsFail() {
        var rubric: PatentRubric = PatentRubric.drafting
        for idx in rubric.criteria.indices { rubric.criteria[idx].score = 5 }
        rubric.criteria[0].score = 2
        guard case .fail = rubric.verdict else {
            XCTFail("Expected fail verdict")
            return
        }
    }
    func testReport_containsTotal() {
        var rubric: PatentRubric = PatentRubric.drafting
        for idx in rubric.criteria.indices { rubric.criteria[idx].score = 4 }
        XCTAssertTrue(rubric.report().contains("32/40"))
    }
}
