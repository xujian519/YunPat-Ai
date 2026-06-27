import XCTest
@testable import YunPatCore
final class PatentRubricTests: XCTestCase {
    func testDrafting_has8Criteria() { XCTAssertEqual(PatentRubric.drafting.criteria.count, 8) }
    func testAll5_returnsPass() { var r = PatentRubric.drafting; for i in r.criteria.indices { r.criteria[i].score = 5 }; guard case .pass = r.verdict else { XCTFail(); return } }
    func testOneAt2_returnsFail() { var r = PatentRubric.drafting; for i in r.criteria.indices { r.criteria[i].score = 5 }; r.criteria[0].score = 2; guard case .fail = r.verdict else { XCTFail(); return } }
    func testReport_containsTotal() { var r = PatentRubric.drafting; for i in r.criteria.indices { r.criteria[i].score = 4 }; XCTAssertTrue(r.report().contains("32/40")) }
}
