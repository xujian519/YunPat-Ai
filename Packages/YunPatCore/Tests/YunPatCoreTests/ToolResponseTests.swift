import XCTest

@testable import YunPatCore

final class ToolResponseTests: XCTestCase {

    // MARK: - okResp

    func testOkResp() {
        let data: JSONValue = .object([
            "path": .string("/tmp/test.txt"),
            "size": .number(42.0)
        ])
        let resp = ToolResponse.okResp(data: data)

        XCTAssertTrue(resp.ok)
        XCTAssertNil(resp.error)
        XCTAssertNil(resp.warnings)
        XCTAssertEqual(resp.data, data)
    }

    // MARK: - errResp

    func testErrResp() {
        let resp = ToolResponse.errResp(
            code: .invalidArgs,
            message: "path required"
        )

        XCTAssertFalse(resp.ok)
        XCTAssertNil(resp.data)
        XCTAssertNil(resp.warnings)
        XCTAssertNotNil(resp.error)
        XCTAssertEqual(resp.error?.code, ToolErrorCode.invalidArgs.rawValue)
        XCTAssertEqual(resp.error?.message, "path required")
        XCTAssertNil(resp.error?.hint)
    }

    // MARK: - errResp with hint

    func testErrRespWithHint() {
        let resp = ToolResponse.errResp(
            code: .writeError,
            message: "Cannot write to /root/secret",
            hint: "Check file permissions and parent directory existence"
        )

        XCTAssertFalse(resp.ok)
        XCTAssertNotNil(resp.error)
        XCTAssertEqual(resp.error?.code, ToolErrorCode.writeError.rawValue)
        XCTAssertEqual(resp.error?.message, "Cannot write to /root/secret")
        XCTAssertEqual(
            resp.error?.hint,
            "Check file permissions and parent directory existence"
        )
    }

    // MARK: - okResp with warnings

    func testOkRespWithWarnings() {
        let warnings: [String] = ["truncated", "partial match"]
        let data: JSONValue = .object([
            "results": .array([
                .string("item1"),
                .string("item2")
            ]),
            "total": .number(100.0)
        ])
        let resp = ToolResponse.okResp(data: data, warnings: warnings)

        XCTAssertTrue(resp.ok)
        XCTAssertNil(resp.error)
        XCTAssertEqual(resp.data, data)
        XCTAssertEqual(resp.warnings, warnings)
    }

    // MARK: - JSON roundtrip

    func testJsonRoundtrip() {
        let original = ToolResponse.errResp(
            code: .ssrfBlocked,
            message: "Private IP range detected",
            hint: "Set allowPrivate to true if accessing internal services"
        )
        let json = original.jsonString()

        guard let roundtripped = ToolResponse.tryParse(json) else {
            XCTFail("tryParse returned nil for valid JSON")
            return
        }

        XCTAssertFalse(roundtripped.ok)
        XCTAssertNil(roundtripped.data)
        XCTAssertNil(roundtripped.warnings)
        XCTAssertNotNil(roundtripped.error)
        XCTAssertEqual(roundtripped.error?.code, ToolErrorCode.ssrfBlocked.rawValue)
        XCTAssertEqual(roundtripped.error?.message, "Private IP range detected")
        XCTAssertEqual(
            roundtripped.error?.hint,
            "Set allowPrivate to true if accessing internal services"
        )
    }

    // MARK: - tryParse: valid JSON

    func testTryParseValidJson() {
        let json: String = """
            {"ok":true,"data":{"items":["a","b","c"],"count":3},"warnings":["stale cache"]}
            """

        let resp = ToolResponse.tryParse(json)

        XCTAssertNotNil(resp)
        XCTAssertTrue(resp?.ok ?? false)
        XCTAssertEqual(
            resp?.data,
            .object([
                "items": .array([.string("a"), .string("b"), .string("c")]),
                "count": .number(3.0)
            ])
        )
        XCTAssertEqual(resp?.warnings, ["stale cache"])
        XCTAssertNil(resp?.error)
    }

    // MARK: - tryParse: garbage

    func testTryParseGarbage() {
        XCTAssertNil(ToolResponse.tryParse("not json at all"))
        XCTAssertNil(ToolResponse.tryParse("{ok:true}"))
        XCTAssertNil(ToolResponse.tryParse(""))
        XCTAssertNil(ToolResponse.tryParse("[]"))
    }

    // MARK: - errResp codes

    func testErrRespCodes() {
        XCTAssertEqual(ToolErrorCode.invalidArgs.rawValue, "INVALID_ARGS")
        XCTAssertEqual(ToolErrorCode.ssrfBlocked.rawValue, "SSRF_BLOCKED")
        XCTAssertEqual(ToolErrorCode.timeout.rawValue, "TIMEOUT")
        XCTAssertEqual(ToolErrorCode.noResults.rawValue, "NO_RESULTS")
        XCTAssertEqual(ToolErrorCode.executionError.rawValue, "EXECUTION_ERROR")
    }

    // MARK: - errResp with warnings

    func testErrRespWithWarnings() {
        let resp = ToolResponse.errResp(
            code: .executionError,
            message: "Something went wrong",
            warnings: ["deprecated API", "stale cache"]
        )

        XCTAssertFalse(resp.ok)
        XCTAssertNil(resp.data)
        XCTAssertNotNil(resp.error)
        XCTAssertEqual(resp.error?.code, ToolErrorCode.executionError.rawValue)
        XCTAssertEqual(resp.warnings, ["deprecated API", "stale cache"])
    }
}
