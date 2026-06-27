import Foundation

/// 升级版 EvaluationEngine — 集成 PatentRubric + FactMarker + TabooDetector
public actor EvaluationEngine {
    private let rubric = PatentRubric.drafting
    private let factEngine = FactMarkerEngine()
    private let tabooDetector = TabooDetector()
    private let twoPassDraft = TwoPassDraft()

    public func evaluate(execution: ExecutionResult, rules: ApplicableRules, facts: StructuredFacts, caseType: String = "drafting") async -> ReviewResult {
        let outputText = execution.artifacts.joined(separator: "\n")
        var issues: [Issue] = []

        // 法条引用检查
        let citedStatutes = extractStatuteCitations(from: execution)
        let expectedStatutes = rules.candidates.filter { $0.sourceLevel <= 2 }
        if citedStatutes.isEmpty && !expectedStatutes.isEmpty {
            issues.append(Issue(severity: .warning, description: "未引用相关法条"))
        }

        // 事实完整性
        for point in facts.inventionPoints {
            if !execution.artifacts.contains(where: { $0.contains(point) }) {
                issues.append(Issue(severity: .warning, description: "遗漏发明点：\(point)"))
            }
        }

        // 规则冲突
        for conflict in rules.conflicts {
            issues.append(Issue(severity: .error, description: "规则冲突：\(conflict.description)"))
        }

        // ── NEW: 禁用词检测 ──
        let taboos = await tabooDetector.detect(in: outputText)
        for t in taboos {
            let sev: IssueSeverity = t.rule.severity == .error ? .error : .warning
            issues.append(Issue(severity: sev, description: "L\(t.line): `\(t.rule.pattern)` — \(t.rule.reason)"))
        }

        // ── NEW: 事实验证 ──
        let inputFacts = await factEngine.extract(from: outputText)
        let factResult = await factEngine.verify(inputFacts: inputFacts, outputText: outputText)
        for lost in factResult.lostFacts {
            issues.append(Issue(severity: .error, description: "丢失关键事实: \(lost.fact)"))
        }

        let verdict = issues.allSatisfy { $0.severity == .warning }
        return ReviewResult(verdict: verdict, issues: issues)
    }

    private func extractStatuteCitations(from result: ExecutionResult) -> [String] {
        let pattern = #"专利法第\d+条"#
        return result.artifacts.flatMap { artifact -> [String] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: artifact, range: NSRange(artifact.startIndex..., in: artifact)).compactMap {
                Range($0.range, in: artifact).map { String(artifact[$0]) }
            }
        }
    }
}
