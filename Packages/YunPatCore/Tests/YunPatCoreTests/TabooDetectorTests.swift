import XCTest

@testable import YunPatCore

final class TabooDetectorTests: XCTestCase {
    func testCleanText_returnsEmpty() async {
        let d = TabooDetector()
        let r = await d.detect(in: "一种装置包括传感模块")
        XCTAssertTrue(r.isEmpty)
    }

    func testBestPhrase_found() async {
        let d = TabooDetector()
        let r = await d.detect(in: "温度最好控制在20℃")
        XCTAssertFalse(r.isEmpty)
        XCTAssertEqual(r.first?.rule.pattern, "最好")
    }
}
