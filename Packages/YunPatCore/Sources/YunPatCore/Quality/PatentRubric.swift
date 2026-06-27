import Foundation

public struct RubricCriterion: Sendable, Codable, Identifiable {
    public let id: String; public let name: String; public let maxScore: Int; public let description: String; public var score: Int = 0; public var notes: String = ""
    public init(id: String, name: String, maxScore: Int = 5, description: String) { self.id = id; self.name = name; self.maxScore = maxScore; self.description = description }
}

public struct PatentRubric: Sendable {
    public var criteria: [RubricCriterion]; public let passThreshold: Int; public let minPerCriterion: Int
    public init(criteria: [RubricCriterion], passThreshold: Int = 32, minPerCriterion: Int = 3) { self.criteria = criteria; self.passThreshold = passThreshold; self.minPerCriterion = minPerCriterion }

    public static let drafting = PatentRubric(criteria: [
        RubricCriterion(id: "statute_accuracy", name: "法条引用准确性", description: "是否正确引用法条号和审查指南章节"),
        RubricCriterion(id: "fact_coverage", name: "事实覆盖完整性", description: "覆盖所有发明点和必要技术特征"),
        RubricCriterion(id: "dependency_valid", name: "引用基础成立性", description: "从属权利要求引用基础正确"),
        RubricCriterion(id: "terminology", name: "术语规范性", description: "使用专利法标准术语"),
        RubricCriterion(id: "clarity", name: "清楚简明性", description: "权利要求清楚、简明"),
        RubricCriterion(id: "scope", name: "保护范围合理性", description: "独立权利要求保护范围合理"),
        RubricCriterion(id: "format", name: "格式合规性", description: "标点、编号、分段符合规范"),
        RubricCriterion(id: "patentability", name: "实际可授权性", description: "具备被授权的合理前景"),
    ])

    public var totalScore: Int { criteria.map(\.score).reduce(0, +) }
    public var maxPossibleScore: Int { criteria.map(\.maxScore).reduce(0, +) }
    public var verdict: RubricVerdict {
        let below = criteria.filter { $0.score < minPerCriterion }
        if !below.isEmpty { return .fail(belowMin: below.map(\.name), totalScore: totalScore) }
        if totalScore >= passThreshold { return .pass }
        if totalScore >= passThreshold - 4 { return .conditionalPass([]) }
        return .fail(belowMin: [], totalScore: totalScore)
    }
    public func report() -> String {
        var lines = ["## 质量评分报告", "", "| 维度 | 得分 | 满分 | 状态 |", "|------|------|------|------|"]
        for c in criteria { let s = c.score >= 4 ? "✅" : c.score >= minPerCriterion ? "⚠️" : "❌"; lines.append("| \(c.name) | \(c.score) | \(c.maxScore) | \(s) |") }
        lines.append(""); lines.append("**总分: \(totalScore)/\(maxPossibleScore)**")
        switch verdict { case .pass: lines.append("**✅ 通过**"); case .conditionalPass(let d): lines.append("**⚠️ 有条件通过** (\(d.joined(separator: "、"))"); case .fail(let d, let s): lines.append("**❌ 不通过** (总分\(s), 薄弱: \(d.joined(separator: "、"))") }
        return lines.joined(separator: "\n")
    }
}

public enum RubricVerdict: Sendable { case pass; case conditionalPass([String]); case fail(belowMin: [String], totalScore: Int) }
