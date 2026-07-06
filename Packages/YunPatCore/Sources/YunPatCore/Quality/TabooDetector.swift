import Foundation

/// 禁用词规则 — 正则匹配、原因、严重级别和替换建议
public struct TabooRule: Sendable {
    public let pattern: String
    public let reason: String
    public let severity: TabooSeverity
    public let suggestion: String

    public init(
        pattern: String,
        reason: String,
        severity: TabooSeverity = .warning,
        suggestion: String = ""
    ) {
        self.pattern = pattern
        self.reason = reason
        self.severity = severity
        self.suggestion = suggestion
    }
}

/// 禁用词严重级别 — error / warning / info
public enum TabooSeverity: String, Sendable {
    case error
    case warning
    case info
}

/// 禁用词检测范围 — claims / description / all
public enum TabooScope: String, Sendable {
    case claims
    case description
    case all
}

/// 禁用词匹配结果 — 匹配的规则、行号和原文
public struct TabooMatch: Sendable {
    public let rule: TabooRule
    public let line: Int
    public let matchedText: String
}

public actor TabooDetector {
    public static let patentTaboos: [TabooRule] = [
        TabooRule(pattern: "最好", reason: "权利要求中禁止模糊程度用语", suggestion: "删除或替换为具体的范围限定"),
        TabooRule(pattern: "可能", reason: "应使用确定性的表述", suggestion: "替换为具体条件"),
        TabooRule(pattern: "等等", reason: "应为穷举或明确开放式表述", suggestion: "使用包括但不限于"),
        TabooRule(pattern: "大约", reason: "数值范围应使用精确端点", severity: .error, suggestion: "使用具体数值"),
        TabooRule(pattern: "约", reason: "数值前不应使用约数", severity: .error, suggestion: "使用精确数值"),
        TabooRule(pattern: "例如", reason: "应列出具体实施方式而非举例", suggestion: "使用包括替代例如"),
        TabooRule(pattern: "优选", reason: "权利要求中不应出现优选表述", suggestion: "说明书中描述"),
        TabooRule(pattern: "尤其是", reason: "权利要求中避免主观强调", suggestion: "删除")
    ]

    private let rules: [TabooRule]

    public init(rules: [TabooRule] = patentTaboos) {
        self.rules = rules
    }

    public func detect(in text: String, scope: TabooScope = .claims) -> [TabooMatch] {
        var matches: [TabooMatch] = []
        for (lineIndex, line) in text.components(separatedBy: .newlines).enumerated() {
            for rule in rules where line.contains(rule.pattern) {
                matches.append(
                    TabooMatch(
                        rule: rule,
                        line: lineIndex + 1,
                        matchedText: line.trimmingCharacters(in: .whitespaces)
                    ))
            }
        }
        return matches
    }

    public func report(for text: String, scope: TabooScope = .claims) -> String {
        let matches = detect(in: text, scope: scope)
        if matches.isEmpty { return "✅ 未检测到禁用词" }
        var lines = ["## 禁用词检测", "", "| 行 | 禁用词 | 严重度 | 建议 |", "|----|--------|--------|------|"]
        for match in matches {
            let severity = match.rule.severity.rawValue
            lines.append("| \(match.line) | `\(match.rule.pattern)` | \(severity) | \(match.rule.suggestion) |")
        }
        lines.append("")
        lines.append("**共 \(matches.count) 处**")
        return lines.joined(separator: "\n")
    }
}
