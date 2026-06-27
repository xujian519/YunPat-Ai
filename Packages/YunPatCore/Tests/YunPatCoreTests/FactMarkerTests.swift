import XCTest
@testable import YunPatCore

final class FactMarkerTests: XCTestCase {
    func testExtract() async {
        let e = FactMarkerEngine()
        let facts = await e.extract(from: "根据 [FACT: 专利法第22条]")
        XCTAssertEqual(facts.count, 1)
        XCTAssertTrue(facts[0].fact.contains("第22条"))
    }

    func testVerifyAllPreserved() async {
        let e = FactMarkerEngine()
        let input = [FactMarker(fact: "第22条", source: "in")]
        let result = await e.verify(
            inputFacts: input, outputText: "第22条规定")
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.preservedCount, 1)
    }

    func testVerifyLost() async {
        let e = FactMarkerEngine()
        let input = [FactMarker(fact: "第22条", source: "in")]
        let result = await e.verify(
            inputFacts: input, outputText: "根据规定")
        XCTAssertFalse(result.passed)
    }
}
