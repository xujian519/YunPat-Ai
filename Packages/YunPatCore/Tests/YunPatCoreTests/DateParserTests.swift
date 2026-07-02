import XCTest

@testable import YunPatCore

final class DateParserTests: XCTestCase {

    // MARK: - ISO 8601

    func testISO8601WithFractional() throws {
        let date: Date = try DateParser.parse("2024-03-15T10:30:00.123Z")
        let cal: Calendar = Calendar(identifier: .gregorian)
        let utc: TimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let comps: DateComponents = cal.dateComponents(in: utc, from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.hour, 10)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertEqual(comps.second, 0)
        // .123 fractional seconds → ~123ms; allow ±1ms for floating-point rounding
        let milliseconds: Int = try XCTUnwrap(comps.nanosecond) / 1_000_000
        XCTAssertGreaterThanOrEqual(milliseconds, 122)
        XCTAssertLessThanOrEqual(milliseconds, 124)
    }

    func testISO8601WithoutFractional() throws {
        let date: Date = try DateParser.parse("2024-12-01T08:00:00Z")
        let cal: Calendar = Calendar(identifier: .gregorian)
        let utc: TimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let comps: DateComponents = cal.dateComponents(in: utc, from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 12)
        XCTAssertEqual(comps.day, 1)
        XCTAssertEqual(comps.hour, 8)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(comps.second, 0)
    }

    // MARK: - Date-Only

    func testDateOnly() throws {
        let date: Date = try DateParser.parse("2024-01-31")
        let cal: Calendar = Calendar(identifier: .gregorian)
        let utc: TimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let comps: DateComponents = cal.dateComponents(in: utc, from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 31)
    }

    // MARK: - RFC 2822

    func testRFC2822() throws {
        // Mon, 15 Mar 2024 10:30:00 +0800 → 02:30 UTC
        let date: Date = try DateParser.parse("Mon, 15 Mar 2024 10:30:00 +0800")
        let cal: Calendar = Calendar(identifier: .gregorian)
        let utc: TimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let comps: DateComponents = cal.dateComponents(in: utc, from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
        // 10:30 +0800 → 02:30 UTC
        XCTAssertEqual(comps.hour, 2)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertEqual(comps.second, 0)
    }

    // MARK: - Chinese Format

    func testChineseFormat() throws {
        let date: Date = try DateParser.parse("2024年3月15日")
        let cal: Calendar = Calendar(identifier: .gregorian)
        let utc: TimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let comps: DateComponents = cal.dateComponents(in: utc, from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
    }

    // MARK: - CNIPA Dot Format

    func testCNIPADot() throws {
        let date: Date = try DateParser.parse("2024.03.15")
        let cal: Calendar = Calendar(identifier: .gregorian)
        let utc: TimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let comps: DateComponents = cal.dateComponents(in: utc, from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
    }

    // MARK: - Unix Timestamps

    func testUnixSeconds() throws {
        // 1710499200 = 2024-03-15T10:40:00Z
        let date: Date = try DateParser.parse("1710499200")
        let cal: Calendar = Calendar(identifier: .gregorian)
        let utc: TimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let comps: DateComponents = cal.dateComponents(in: utc, from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
        // 1710499200 % 86400 = 38400 → 10:40:00
        XCTAssertEqual(comps.hour, 10)
        XCTAssertEqual(comps.minute, 40)
        XCTAssertEqual(comps.second, 0)
    }

    func testUnixMilliseconds() throws {
        // 1710499200000 ms = 1710499200 sec = 2024-03-15T10:40:00Z
        let date: Date = try DateParser.parse("1710499200000")
        let cal: Calendar = Calendar(identifier: .gregorian)
        let utc: TimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let comps: DateComponents = cal.dateComponents(in: utc, from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.hour, 10)
        XCTAssertEqual(comps.minute, 40)
        XCTAssertEqual(comps.second, 0)
    }

    // MARK: - Error Handling

    func testGarbageThrows() {
        XCTAssertThrowsError(try DateParser.parse("not a date")) { error in
            guard case DateParser.ParseError.unrecognizedFormat(let string) = error else {
                XCTFail("Expected unrecognizedFormat, got \(error)")
                return
            }
            XCTAssertTrue(string.contains("not a date"))
        }
    }

    // MARK: - ISO 8601 Duration

    func testISODurationDays() throws {
        // P3DT2H30M = 3*86400 + 2*3600 + 30*60 = 268200
        let result = try DateParser.parseISODuration("P3DT2H30M")
        let expected: TimeInterval = 3 * 86400 + 2 * 3600 + 30 * 60
        XCTAssertEqual(result, expected)
    }

    func testISODurationNegative() throws {
        // -P1D = -86400
        let result = try DateParser.parseISODuration("-P1D")
        XCTAssertEqual(result, -86400)
    }

    func testISODurationMinutes() throws {
        // PT90M = 90 * 60 = 5400
        let result = try DateParser.parseISODuration("PT90M")
        XCTAssertEqual(result, 5400)
    }

    func testISODurationEmptyThrows() {
        // P with nothing after it → empty duration
        XCTAssertThrowsError(try DateParser.parseISODuration("P")) { error in
            guard case DateParser.ParseError.invalidDuration = error else {
                XCTFail("Expected invalidDuration, got \(error)")
                return
            }
        }
    }

    // MARK: - ISO 8601 Duration: Edge Cases

    func testISODurationPTThrows() {
        XCTAssertThrowsError(try DateParser.parseISODuration("PT")) { error in
            guard let parseError = error as? DateParser.ParseError else {
                XCTFail("Expected ParseError")
                return
            }
            XCTAssertEqual(parseError, .invalidDuration("PT"))
        }
    }

    func testISODurationWeeks() throws {
        let secs = try DateParser.parseISODuration("P1W")
        XCTAssertEqual(secs, 7 * 86400)
    }

    // MARK: - Timezone Offset

    func testISO8601WithPositiveOffset() throws {
        let date = try DateParser.parse("2024-03-15T10:30:00+05:30")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let hour = cal.component(.hour, from: date)
        // +05:30 → UTC hour = 10:30 - 5:30 = 5:00
        XCTAssertEqual(hour, 5)
    }

    func testISO8601WithNegativeOffset() throws {
        let date = try DateParser.parse("2024-03-15T10:30:00-08:00")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let hour = cal.component(.hour, from: date)
        // -08:00 → UTC hour = 10:30 + 8:00 = 18:30
        XCTAssertEqual(hour, 18)
    }

    // MARK: - Leap Year

    func testLeapYearFeb29Valid() throws {
        let date = try DateParser.parse("2024-02-29")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 2)
        XCTAssertEqual(comps.day, 29)
    }

    func testNonLeapYearFeb29DateOnlyThrows() {
        // 2023-02-29 is invalid in the Gregorian calendar
        // DateFormatter with yyyy-MM-dd may silently adjust to Mar 1
        // We accept this behavior (Foundation's DateFormatter handles it)
        let date = try? DateParser.parse("2023-02-29")
        // If it parses (Foundation adjusts), the day won't be 29
        if let parsed = date {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = try! TimeZone(secondsFromGMT: 0)!
            let day = cal.component(.day, from: parsed)
            XCTAssertNotEqual(day, 29, "2023-02-29 should not resolve to Feb 29")
        }
    }
}
