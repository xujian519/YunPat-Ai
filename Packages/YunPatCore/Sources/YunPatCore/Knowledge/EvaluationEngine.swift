import Foundation

/// 升级版 EvaluationEngine — 集成 PatentRubric 评分 + FactMarker + TabooDetector
public actor EvaluationEngine {
    private let rubric: PatentRubric
    private let factEngine: FactMarkerEngine = FactMarkerEngine()
    private let tabooDetector: TabooDetector = TabooDetector()

    public init(rubric: PatentRubric = .drafting) {
        self.rubric = rubric
    }

    /// 评估执行结果，返回带 rubric 维度得分的审查结果
    public func evaluate(
        execution: ExecutionResult, rules: ApplicableRules,
        facts: StructuredFacts
    ) async -> ReviewResult {
        let outputText: String = execution.artifacts.joined(separator: "\n")
        var issues: [Issue] = []
        var rubric: PatentRubric = self.rubric

        rubric = await scoreStatuteAccuracy(rules: rules, execution: execution, rubric: rubric, issues: &issues)
        rubric = scoreFactCoverage(facts: facts, execution: execution, rubric: rubric, issues: &issues)
        rubric = await scoreTerminology(outputText: outputText, rubric: rubric, issues: &issues)
        rubric = rubric.withScore(id: "clarity", score: scoreClarity(outputText))
        rubric = rubric.withScore(id: "format", score: scoreFormat(outputText))
        rubric = rubric.withScore(id: "dependency_valid", score: 3)
        rubric = rubric.withScore(id: "scope", score: 3)
        rubric = rubric.withScore(id: "patentability", score: 3)

        for conflict in rules.conflicts {
            issues.append(Issue(severity: .error, description: "规则冲突：\(conflict.description)"))
        }

        let inputFacts: [FactMarker] = await factEngine.extract(from: outputText)
        let factResult: FactVerificationResult = await factEngine.verify(inputFacts: inputFacts, outputText: outputText)
        for lost in factResult.lostFacts {
            issues.append(Issue(severity: .error, description: "丢失关键事实: \(lost.fact)"))
        }

        let verdict: RubricVerdict = rubric.verdict
        let passed: Bool = if case .pass = verdict { true } else { false }
        return ReviewResult(verdict: passed, issues: issues, rubric: rubric, rubricVerdict: verdict)
    }

    private func scoreStatuteAccuracy(
        rules: ApplicableRules, execution: ExecutionResult, rubric: PatentRubric,
        issues: inout [Issue]
    ) async -> PatentRubric {
        let citedStatutes: [String] = extractStatuteCitations(from: execution)
        let expectedStatutes: [RuleCandidate] = rules.candidates.filter { $0.sourceLevel <= 2 }
        var newRubric: PatentRubric = rubric
        if citedStatutes.isEmpty && !expectedStatutes.isEmpty {
            issues.append(Issue(severity: .warning, description: "未引用相关法条"))
            newRubric = newRubric.withScore(id: "statute_accuracy", score: 1)
        } else if !citedStatutes.isEmpty {
            let matched: [String] = citedStatutes.filter { citation in
                expectedStatutes.contains(where: { citation.contains($0.title.prefix(8)) })
            }
            newRubric = newRubric.withScore(id: "statute_accuracy", score: min(5, max(2, matched.count + 1)))
        } else {
            newRubric = newRubric.withScore(id: "statute_accuracy", score: 3)
        }
        return newRubric
    }

    private func scoreFactCoverage(
        facts: StructuredFacts, execution: ExecutionResult, rubric: PatentRubric,
        issues: inout [Issue]
    ) -> PatentRubric {
        var coveredPoints: Int = 0
        for point in facts.inventionPoints {
            if execution.artifacts.contains(where: { $0.contains(point) }) {
                coveredPoints += 1
            } else {
                issues.append(Issue(severity: .warning, description: "遗漏发明点：\(point)"))
            }
        }
        let factCoverage: Int =
            facts.inventionPoints.isEmpty
            ? 3
            : Int(Double(coveredPoints) / Double(facts.inventionPoints.count) * 5)
        return rubric.withScore(id: "fact_coverage", score: min(5, max(1, factCoverage)))
    }

    private func scoreTerminology(
        outputText: String, rubric: PatentRubric, issues: inout [Issue]
    ) async -> PatentRubric {
        let taboos: [TabooMatch] = await tabooDetector.detect(in: outputText)
        for taboo in taboos {
            let sev: IssueSeverity = taboo.rule.severity == .error ? .error : .warning
            let descriptionText: String = "L\(taboo.line): `\(taboo.rule.pattern)` — \(taboo.rule.reason)"
            issues.append(Issue(severity: sev, description: descriptionText))
        }
        if taboos.isEmpty {
            return rubric.withScore(id: "terminology", score: 5)
        }
        let deduction: Int =
            taboos.filter { $0.rule.severity == .error }.count * 2
            + taboos.filter { $0.rule.severity == .warning }.count
        return rubric.withScore(id: "terminology", score: max(1, 5 - deduction))
    }

    private func scoreClarity(_ text: String) -> Int {
        let separators: CharacterSet = CharacterSet(charactersIn: "。！？\n")
        let sentences: [String] = text.components(separatedBy: separators)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if sentences.isEmpty { return 1 }
        let avgLength: Int = sentences.map(\.count).reduce(0, +) / sentences.count
        if avgLength > 200 { return 2 }
        if avgLength > 120 { return 3 }
        if avgLength > 50 { return 4 }
        return 5
    }

    private func scoreFormat(_ text: String) -> Int {
        let hasNumberedClaims: Bool = text.contains("1.") || text.contains("1、")
        let hasSeparation: Bool = text.contains("其特征在于")
        var score: Int = 3
        if hasNumberedClaims { score += 1 }
        if hasSeparation { score += 1 }
        return min(5, score)
    }

    private func extractStatuteCitations(from result: ExecutionResult) -> [String] {
        let pattern: String = #"专利法第\d+条"#
        return result.artifacts.flatMap { artifact -> [String] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: artifact, range: NSRange(artifact.startIndex..., in: artifact)).compactMap {
                Range($0.range, in: artifact).map { String(artifact[$0]) }
            }
        }
    }
}
