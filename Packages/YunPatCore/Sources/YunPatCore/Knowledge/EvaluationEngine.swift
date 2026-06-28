import Foundation

/// 升级版 EvaluationEngine — 集成 PatentRubric 评分 + FactMarker + TabooDetector
public actor EvaluationEngine {
    private let rubric: PatentRubric
    private let factEngine = FactMarkerEngine()
    private let tabooDetector = TabooDetector()

    public init(rubric: PatentRubric = .drafting) {
        self.rubric = rubric
    }

    /// 评估执行结果，返回带 rubric 维度得分的审查结果
    public func evaluate(execution: ExecutionResult, rules: ApplicableRules, facts: StructuredFacts) async -> ReviewResult {
        let outputText = execution.artifacts.joined(separator: "\n")
        var issues: [Issue] = []
        var rubric = self.rubric

        // ── 维度 1: 法条引用准确性 ──
        let citedStatutes = extractStatuteCitations(from: execution)
        let expectedStatutes = rules.candidates.filter { $0.sourceLevel <= 2 }
        if citedStatutes.isEmpty && !expectedStatutes.isEmpty {
            issues.append(Issue(severity: .warning, description: "未引用相关法条"))
            rubric = rubric.withScore(id: "statute_accuracy", score: 1)
        } else if !citedStatutes.isEmpty {
            let matched = citedStatutes.filter { s in expectedStatutes.contains(where: { s.contains($0.title.prefix(8)) }) }
            rubric = rubric.withScore(id: "statute_accuracy", score: min(5, max(2, matched.count + 1)))
        } else {
            rubric = rubric.withScore(id: "statute_accuracy", score: 3)
        }

        // ── 维度 2: 事实覆盖完整性 ──
        var coveredPoints = 0
        for point in facts.inventionPoints {
            if execution.artifacts.contains(where: { $0.contains(point) }) {
                coveredPoints += 1
            } else {
                issues.append(Issue(severity: .warning, description: "遗漏发明点：\(point)"))
            }
        }
        let factCoverage = facts.inventionPoints.isEmpty ? 3 : Int(Double(coveredPoints) / Double(facts.inventionPoints.count) * 5)
        rubric = rubric.withScore(id: "fact_coverage", score: min(5, max(1, factCoverage)))

        // ── 维度 3: 术语规范性（TabooDetector）──
        let taboos = await tabooDetector.detect(in: outputText)
        for t in taboos {
            let sev: IssueSeverity = t.rule.severity == .error ? .error : .warning
            issues.append(Issue(severity: sev, description: "L\(t.line): `\(t.rule.pattern)` — \(t.rule.reason)"))
        }
        let termScore = taboos.isEmpty ? 5 : max(1, 5 - taboos.filter { $0.rule.severity == .error }.count * 2 - taboos.filter { $0.rule.severity == .warning }.count)
        rubric = rubric.withScore(id: "terminology", score: termScore)

        // ── 维度 4: 清楚简明性 ──
        let clarityScore = scoreClarity(outputText)
        rubric = rubric.withScore(id: "clarity", score: clarityScore)

        // ── 维度 5: 格式合规性 ──
        let formatScore = scoreFormat(outputText)
        rubric = rubric.withScore(id: "format", score: formatScore)

        // ── 维度 6-8: 默认评分（LLM 辅助判断）──
        rubric = rubric.withScore(id: "dependency_valid", score: 3)
        rubric = rubric.withScore(id: "scope", score: 3)
        rubric = rubric.withScore(id: "patentability", score: 3)

        // ── 规则冲突 ──
        for conflict in rules.conflicts {
            issues.append(Issue(severity: .error, description: "规则冲突：\(conflict.description)"))
        }

        // ── 事实验证 ──
        let inputFacts = await factEngine.extract(from: outputText)
        let factResult = await factEngine.verify(inputFacts: inputFacts, outputText: outputText)
        for lost in factResult.lostFacts {
            issues.append(Issue(severity: .error, description: "丢失关键事实: \(lost.fact)"))
        }

        let verdict = rubric.verdict
        let passed = if case .pass = verdict { true } else { false }
        return ReviewResult(verdict: passed, issues: issues, rubric: rubric, rubricVerdict: verdict)
    }

    private func scoreClarity(_ text: String) -> Int {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: "。！？\n")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if sentences.isEmpty { return 1 }
        let avgLength = sentences.map(\.count).reduce(0, +) / sentences.count
        if avgLength > 200 { return 2 }
        if avgLength > 120 { return 3 }
        if avgLength > 50 { return 4 }
        return 5
    }

    private func scoreFormat(_ text: String) -> Int {
        let hasNumberedClaims = text.contains("1.") || text.contains("1、")
        let hasSeparation = text.contains("其特征在于")
        var score = 3
        if hasNumberedClaims { score += 1 }
        if hasSeparation { score += 1 }
        return min(5, score)
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
