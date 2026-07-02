import Foundation

// MARK: - Multi-Format Date Parser

/// 多格式日期解析器 — 对齐 Osaurus time 工具
/// 支持 ISO 8601、RFC 2822、yyyy-MM-dd、中文日期、Unix 时间戳等多种格式
public enum DateParser: Sendable {

    // MARK: - Errors

    public enum ParseError: Error, Equatable {
        case unrecognizedFormat(String)
        case invalidDuration(String)
    }

    // MARK: - Formatters (nonisolated(unsafe) for Swift 6 concurrency)
    // DateFormatter and ISO8601DateFormatter are not Sendable in the SDK,
    // but they are only accessed from synchronous static parse() calls.

    private nonisolated(unsafe) static let iso8601Fractional: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    private nonisolated(unsafe) static let iso8601NoFractional: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()

    private static let dateOnlyFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    private static let rfc2822Fmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    private static let chineseFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy年M月d日"
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.locale = Locale(identifier: "zh_CN")
        return fmt
    }()

    private static let cnipaDotFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy.MM.dd"
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()
    // MARK: - Date Parsing

    /// 解析日期字符串，按优先级尝试 8 种格式
    /// - ISO 8601 with fractional seconds
    /// - ISO 8601 without fractional seconds
    /// - Date-only (yyyy-MM-dd)
    /// - RFC 2822
    /// - Chinese (yyyy年M月d日)
    /// - CNIPA dot (yyyy.MM.dd)
    /// - Unix seconds (10 digits)
    /// - Unix milliseconds (13 digits)
    public static func parse(_ input: String) throws -> Date {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.unrecognizedFormat("empty") }

        if let date = iso8601Fractional.date(from: trimmed) { return date }
        if let date = iso8601NoFractional.date(from: trimmed) { return date }
        if let date = dateOnlyFmt.date(from: trimmed) { return date }
        if let date = rfc2822Fmt.date(from: trimmed) { return date }
        if let date = chineseFmt.date(from: trimmed) { return date }
        if let date = cnipaDotFmt.date(from: trimmed) { return date }

        // Unix seconds: 10 digits, year range 2001–2286
        if trimmed.count == 10, let timestamp = Double(trimmed),
            timestamp > 978_307_200, timestamp < 9_999_999_999
        {  // swiftlint:disable:this opening_brace
            return Date(timeIntervalSince1970: timestamp)
        }

        // Unix milliseconds: 13 digits
        if trimmed.count == 13, let timestamp = Double(trimmed),
            timestamp > 978_307_200_000, timestamp < 9_999_999_999_999
        {  // swiftlint:disable:this opening_brace
            return Date(timeIntervalSince1970: timestamp / 1000.0)
        }

        throw ParseError.unrecognizedFormat(trimmed)
    }

    // MARK: - ISO 8601 Duration

    /// 解析 ISO 8601 Duration (e.g. P3DT2H30M, PT90M, -P1D, P1Y2M)
    /// Returns total seconds as TimeInterval
    public static func parseISODuration(_ input: String) throws -> TimeInterval {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.invalidDuration("empty") }

        var negative: Bool = false
        var remaining: String = trimmed
        if remaining.hasPrefix("-") {
            negative = true
            remaining = String(remaining.dropFirst())
        }

        guard remaining.hasPrefix("P") else { throw ParseError.invalidDuration(trimmed) }
        remaining = String(remaining.dropFirst())
        // "PT" (仅时间指示符，无实际值) → 无效
        if remaining == "T" { throw ParseError.invalidDuration(trimmed) }
        if remaining.isEmpty { throw ParseError.invalidDuration(trimmed) }
        var seconds: TimeInterval = 0
        var current: String = ""
        var inTime: Bool = false
        for char in remaining {
            if char == "T" {
                inTime = true
                continue
            }
            if char.isNumber || char == "." {
                current.append(char)
            } else {
                guard let val = Double(current), !current.isEmpty else {
                    throw ParseError.invalidDuration(trimmed)
                }
                switch char {
                case "Y": seconds += val * 365.25 * 86400
                case "M": seconds += val * (inTime ? 60 : 30.4375 * 86400)
                case "W": seconds += val * 7 * 86400
                case "D": seconds += val * 86400
                case "H": seconds += val * 3600
                case "S": seconds += val
                default: throw ParseError.invalidDuration(trimmed)
                }
                current = ""
            }
        }

        if !current.isEmpty { throw ParseError.invalidDuration(trimmed) }
        return negative ? -seconds : seconds
    }
}
