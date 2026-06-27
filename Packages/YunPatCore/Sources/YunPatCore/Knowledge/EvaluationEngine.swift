import Foundation

public actor EvaluationEngine {
    public func evaluate(execution: ExecutionResult, rules: ApplicableRules, facts: StructuredFacts) -> ReviewResult {
        var issues: [Issue] = []
        let citedStatutes = extractStatuteCitations(from: execution)
        let expectedStatutes = rules.candidates.filter { $0.sourceLevel <= 2 }
        if citedStatutes.isEmpty && !expectedStatutes.isEmpty {
            issues.append(Issue(severity: .warning, description: "未引用相关法条"))
        }
        for point in facts.inventionPoints {
            if !execution.artifacts.contains(where: { $0.contains(point) }) {
                issues.append(Issue(severity: .warning, description: "遗漏发明点：\(point)"))
            }
        }
        for conflict in rules.conflicts {
            issues.append(Issue(severity: .error, description: "规则冲突：\(conflict.description)"))
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
