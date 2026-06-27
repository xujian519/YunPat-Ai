# YunPat-Ai Plan 6: Nuo-IDE Quality System Integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 Nuo-IDE (Zed) 的质量基础设施引入 YunPat-Ai——PatentRubric 多维度评分量表、FactMarker [FACT] 标注链、TypedAction 类型化事件系统、TabooDetector 禁用词检测、TwoPassDraft 双轮草稿流程。

**Architecture:** 在 YunPatCore 中新增 `Quality/` 目录集中管理质量基础设施。升级 `EvaluationEngine` 使用 Rubric 评分替代简单 pass/fail。引入 `FactMarker` 到 PatentLoop Step 4→5 的检查流程。

**Tech Stack:** Swift 6, no external dependencies

---

## 文件结构（Plan 6 新增/修改）

```
YunPat-Ai/
├── Packages/YunPatCore/Sources/YunPatCore/
│   ├── Quality/                           ← 新建：质量基础设施
│   │   ├── PatentRubric.swift                  # 8 维评分量表
│   │   ├── FactMarker.swift                    # [FACT] 标注系统
│   │   ├── TabooDetector.swift                 # 禁用词检测
│   │   ├── TypedAction.swift                   # 类型化事件系统
│   │   └── TwoPassDraft.swift                  # 双轮草稿流程
│   ├── Patent/
│   │   └── ChecklistEngine.swift               # 修改：接入 Rubric
│   ├── Knowledge/
│   │   └── EvaluationEngine.swift              # 修改：使用 Rubric + FactMarker + TabooDetector
│   └── Loop/
│       └── PatentLoopEngine.swift              # 修改：Step 3.5 诊断轮
├── App/Views/
│   ├── ContentView.swift                       # 修改：TypedAction 替换 NotificationCenter
│   ├── TabBar.swift                            # 修改：TypedAction 监听
│   └── CollaborationPanel.swift               # 修改：显示 Rubric 评分
└── Packages/YunPatCore/Tests/YunPatCoreTests/
    ├── PatentRubricTests.swift
    ├── FactMarkerTests.swift
    ├── TabooDetectorTests.swift
    └── TypedActionTests.swift
```

---

## Phase A: 质量基础设施（Tasks 1-5）

### Task 1: 实现 PatentRubric（8 维评分量表）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Quality/PatentRubric.swift`
- Create: `Tests/YunPatCoreTests/PatentRubricTests.swift`

**Code:**

```swift
// Quality/PatentRubric.swift
import Foundation

// ── 评分维度 ──
public struct RubricCriterion: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let maxScore: Int
    public let description: String
    public var score: Int = 0
    public var notes: String = ""

    public init(id: String, name: String, maxScore: Int = 5, description: String) {
        self.id = id; self.name = name; self.maxScore = maxScore; self.description = description
    }
}

// ── 评分量表 ──
public struct PatentRubric: Sendable {
    public var criteria: [RubricCriterion]
    public let passThreshold: Int        // 总分阈值
    public let minPerCriterion: Int      // 单维最低分

    public init(criteria: [RubricCriterion], passThreshold: Int = 32, minPerCriterion: Int = 3) {
        self.criteria = criteria; self.passThreshold = passThreshold; self.minPerCriterion = minPerCriterion
    }

    /// 预设：专利申请撰写评分量表
    public static let drafting = PatentRubric(criteria: [
        RubricCriterion(id: "statute_accuracy", name: "法条引用准确性", description: "是否正确引用法条号和审查指南章节"),
        RubricCriterion(id: "fact_coverage", name: "事实覆盖完整性", description: "是否覆盖所有发明点和必要技术特征"),
        RubricCriterion(id: "dependency_valid", name: "引用基础成立性", description: "从属权利要求引用基础是否正确"),
        RubricCriterion(id: "terminology", name: "术语规范性", description: "是否使用专利法标准术语"),
        RubricCriterion(id: "clarity", name: "清楚简明性", description: "权利要求是否清楚、简明"),
        RubricCriterion(id: "scope", name: "保护范围合理性", description: "独立权利要求保护范围是否合理"),
        RubricCriterion(id: "format", name: "格式合规性", description: "标点、编号、分段是否符合规范"),
        RubricCriterion(id: "patentability", name: "实际可授权性", description: "是否具备被授权的合理前景"),
    ])

    /// 预设：OA 答复评分量表
    public static let oaResponse = PatentRubric(criteria: [
        RubricCriterion(id: "oa_point_addressed", name: "OA 要点回应", description: "是否逐条回应审查意见通知书的每项驳回理由"),
        RubricCriterion(id: "argument_strength", name: "论据充分性", description: "修改依据和争辩理由是否充分有力"),
        RubricCriterion(id: "amendment_scope", name: "修改合规性", description: "修改是否在原始申请范围内"),
        RubricCriterion(id: "statute_cited", name: "法条引用", description: "是否正确引用专利法及审查指南相关条款"),
        RubricCriterion(id: "case_support", name: "案例支撑", description: "是否引用相关复审/无效决定或判例支持"),
        RubricCriterion(id: "language_quality", name: "语言严谨性", description: "表述是否准确、无歧义、符合法律文书规范"),
        RubricCriterion(id: "completeness", name: "完整性", description: "是否覆盖所有必要的修改和争辩要点"),
        RubricCriterion(id: "practical_value", name: "实务价值", description: "答复策略在实务中是否可行有效"),
    ])

    /// 预设：无效宣告分析评分量表
    public static let invalidation = PatentRubric(criteria: [
        RubricCriterion(id: "grounds_valid", name: "无效理由合法性", description: "无效理由是否符合专利法第45条及细则第65条规定"),
        RubricCriterion(id: "evidence_chain", name: "证据链完整性", description: "证据是否形成完整链条"),
        RubricCriterion(id: "novelty_analysis", name: "新颖性分析", description: "新颖性对比分析是否准确"),
        RubricCriterion(id: "creativity_analysis", name: "创造性分析", description: "三步法分析是否严密"),
        RubricCriterion(id: "disclosure_analysis", name: "充分公开分析", description: "说明书充分公开分析是否到位"),
        RubricCriterion(id: "support_analysis", name: "清楚支持分析", description: "权利要求清楚/支持分析是否准确"),
        RubricCriterion(id: "defense_anticipation", name: "防御预判", description: "是否预判专利权人可能的抗辩理由"),
        RubricCriterion(id: "practical_value", name: "实务可行性", description: "无效策略在复审委实务中是否可行"),
    ])

    /// 总分
    public var totalScore: Int { criteria.map(\.score).reduce(0, +) }
    public var maxPossibleScore: Int { criteria.map(\.maxScore).reduce(0, +) }

    /// 判定
    public var verdict: RubricVerdict {
        let belowMin = criteria.filter { $0.score < minPerCriterion }
        if totalScore >= passThreshold && belowMin.isEmpty { return .pass }
        if totalScore >= passThreshold - 4 { return .conditionalPass(belowMin.map(\.name)) }
        return .fail(belowMin: belowMin.map(\.name), totalScore: totalScore)
    }

    /// 格式化报告
    public func report() -> String {
        var lines = ["## 质量评分报告", ""]
        lines.append("| 维度 | 得分 | 满分 | 状态 |")
        lines.append("|------|------|------|------|")
        for c in criteria {
            let status = c.score >= 4 ? "✅" : c.score >= minPerCriterion ? "⚠️" : "❌"
            lines.append("| \(c.name) | \(c.score) | \(c.maxScore) | \(status) |")
        }
        lines.append("")
        lines.append("**总分: \(totalScore)/\(maxPossibleScore)**")
        lines.append("**阈值: \(passThreshold) 分, 单维最低 \(minPerCriterion) 分**")
        switch verdict {
        case .pass: lines.append("**判定: ✅ 通过**")
        case .conditionalPass(let dims): lines.append("**判定: ⚠️ 有条件通过** (薄弱维度: \(dims.joined(separator: "、")))")
        case .fail(let dims, let score): lines.append("**判定: ❌ 不通过** (总分 \(score), 未达标维度: \(dims.joined(separator: "、"))")
        }
        return lines.joined(separator: "\n")
    }
}

public enum RubricVerdict: Sendable {
    case pass
    case conditionalPass([String])    // 有条件通过 + 薄弱的维度名
    case fail(belowMin: [String], totalScore: Int)
}
```

**Tests:**

```swift
// PatentRubricTests.swift
final class PatentRubricTests: XCTestCase {
    func testDraftingRubric_has8Criteria() {
        let rubric = PatentRubric.drafting
        XCTAssertEqual(rubric.criteria.count, 8)
    }
    
    func testAllPass_returnsPass() {
        var rubric = PatentRubric.drafting
        for i in rubric.criteria.indices { rubric.criteria[i].score = 5 }
        guard case .pass = rubric.verdict else { XCTFail(); return }
    }
    
    func testOneDimensionBelow3_returnsFail() {
        var rubric = PatentRubric.drafting
        for i in rubric.criteria.indices { rubric.criteria[i].score = 5 }
        rubric.criteria[0].score = 2
        guard case .fail = rubric.verdict else { XCTFail("应判定不通过"); return }
    }
    
    func testReport_formatsCorrectly() {
        var rubric = PatentRubric.drafting
        for i in rubric.criteria.indices { rubric.criteria[i].score = 4 }
        let report = rubric.report()
        XCTAssertTrue(report.contains("32/40"))
        XCTAssertTrue(report.contains("通过"))
    }
}
```

- [ ] Write implementation + tests
- [ ] `cd Packages/YunPatCore && swift test --filter PatentRubricTests` (4 PASS)
- [ ] Commit: `feat: implement PatentRubric — 8-dimension scoring system for patent quality`

### Task 2: 实现 FactMarker（[FACT] 标注链）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Quality/FactMarker.swift`
- Create: `Tests/YunPatCoreTests/FactMarkerTests.swift`

**Code:**

```swift
// Quality/FactMarker.swift
import Foundation

/// [FACT] 标记 — 确保关键事实在 AI 迭代中不被篡改
public struct FactMarker: Sendable, Codable {
    public let id: UUID
    public let fact: String
    public let source: String         // 来源（法条号/决定号/案号）
    public let location: FactLocation  // 在文档中的位置
    public let verified: Bool
    public let verifiedBy: String?

    public init(fact: String, source: String, location: FactLocation = .inline,
                verified: Bool = false, verifiedBy: String? = nil) {
        self.id = UUID(); self.fact = fact; self.source = source
        self.location = location; self.verified = verified; self.verifiedBy = verifiedBy
    }
}

public enum FactLocation: String, Sendable, Codable {
    case inline      // 内联标注 [FACT: ...]
    case footnote    // 脚注
    case appendix    // 附录
}

/// FactMarker 引擎 — 提取、验证、对比
public actor FactMarkerEngine {
    public init() {}

    /// 从文本中提取所有 [FACT: ...] 标记
    public func extract(from text: String) -> [FactMarker] {
        let pattern = #"\[FACT:\s*([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return FactMarker(fact: String(text[range]), source: "inline")
        }
    }

    /// 标注文本 — 为事实添加 [FACT: source] 标记
    public func mark(_ text: String, fact: String, source: String) -> String {
        text.replacingOccurrences(of: fact, with: "[FACT: \(source)]\(fact)[/FACT]")
    }

    /// 验证 — 对比输入和输出中的 [FACT] 标记，检查是否全部保留
    public func verify(inputFacts: [FactMarker], outputText: String) -> FactVerificationResult {
        let outputFacts = extract(from: outputText)
        let inputIDs = Set(inputFacts.map(\.fact))
        let outputIDs = Set(outputFacts.map(\.fact))

        let preserved = inputIDs.intersection(outputIDs)
        let lost = inputIDs.subtracting(outputIDs)
        let added = outputIDs.subtracting(inputIDs)

        let lostMarkers = inputFacts.filter { lost.contains($0.fact) }
        let addedMarkers = outputFacts.filter { added.contains($0.fact) }

        return FactVerificationResult(
            passed: lost.isEmpty,
            preservedCount: preserved.count,
            lostFacts: lostMarkers,
            addedFacts: addedMarkers
        )
    }
}

public struct FactVerificationResult: Sendable {
    public let passed: Bool
    public let preservedCount: Int
    public let lostFacts: [FactMarker]
    public let addedFacts: [FactMarker]

    public var summary: String {
        if passed { return "✅ 全部 \(preservedCount) 个事实已保留" }
        return "❌ 丢失 \(lostFacts.count) 个事实: \(lostFacts.map(\.fact).joined(separator: "; "))"
    }
}
```

**Tests:**

```swift
// FactMarkerTests.swift
final class FactMarkerTests: XCTestCase {
    func testExtract_singleFact() async {
        let engine = FactMarkerEngine()
        let text = "根据 [FACT: 专利法第22条第3款] 三步法判断"
        let facts = await engine.extract(from: text)
        XCTAssertEqual(facts.count, 1)
        XCTAssertTrue(facts[0].fact.contains("第22条"))
    }
    
    func testVerify_allPreserved() async {
        let engine = FactMarkerEngine()
        let input = [FactMarker(fact: "专利法第22条第3款", source: "input"),
                     FactMarker(fact: "审查指南第二部分第四章", source: "input")]
        let output = "根据专利法第22条第3款和审查指南第二部分第四章..."
        let result = await engine.verify(inputFacts: input, outputText: output)
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.preservedCount, 2)
    }
    
    func testVerify_lostFact_fails() async {
        let engine = FactMarkerEngine()
        let input = [FactMarker(fact: "专利法第22条第3款", source: "input")]
        let output = "根据相关规定..."  // 法条丢失
        let result = await engine.verify(inputFacts: input, outputText: output)
        XCTAssertFalse(result.passed)
    }
}
```

- [ ] Write implementation + tests (3 PASS)
- [ ] Commit

### Task 3: 实现 TabooDetector（专利禁用词检测）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Quality/TabooDetector.swift`
- Create: `Tests/YunPatCoreTests/TabooDetectorTests.swift`

**Code:**

```swift
// Quality/TabooDetector.swift
import Foundation

/// 单一禁用词规则
public struct TabooRule: Sendable {
    public let pattern: String
    public let reason: String
    public let severity: TabooSeverity
    public let suggestion: String
    public let appliesTo: [TabooScope]  // 适用范围

    public init(pattern: String, reason: String, severity: TabooSeverity = .warning,
                suggestion: String = "", appliesTo: [TabooScope] = [.claims]) {
        self.pattern = pattern; self.reason = reason; self.severity = severity
        self.suggestion = suggestion; self.appliesTo = appliesTo
    }
}

public enum TabooSeverity: String, Sendable { case error; case warning; case info }
public enum TabooScope: String, Sendable { case claims; case description; case all }

/// 检测结果
public struct TabooMatch: Sendable {
    public let rule: TabooRule
    public let line: Int
    public let matchedText: String
}

/// 禁用词检测器
public actor TabooDetector {
    /// 专利领域内置禁用词表
    public static let patentTaboos: [TabooRule] = [
        TabooRule(pattern: "最好", reason: "权利要求中禁止使用模糊程度用语", suggestion: "删除或替换为具体的范围限定", appliesTo: [.claims]),
        TabooRule(pattern: "可能", reason: "应使用确定性的表述", suggestion: "替换为'可以'或添加具体条件", appliesTo: [.claims]),
        TabooRule(pattern: "等等", reason: "应为穷举或明确开放式表述", suggestion: "穷举所有情况或使用'包括但不限于'", appliesTo: [.claims, .description]),
        TabooRule(pattern: "大约", reason: "数值范围应使用精确端点", suggestion: "使用具体的数值或公差范围", appliesTo: [.claims, .description]),
        TabooRule(pattern: "约", reason: "数值前不应使用约数", suggestion: "使用精确数值", appliesTo: [.claims]),
        TabooRule(pattern: "例如", reason: "应列出具体实施方式而非举例", suggestion: "使用'包括'替代'例如'并列出具体方案", appliesTo: [.description]),
        TabooRule(pattern: "优选", reason: "权利要求中不应出现优选表述", suggestion: "在说明书中描述,权利要求中使用明确限定", appliesTo: [.claims]),
        TabooRule(pattern: "尤其是", reason: "权利要求中避免主观强调", appliesTo: [.claims]),
    ]

    private let rules: [TabooRule]

    public init(rules: [TabooRule] = patentTaboos) { self.rules = rules }

    /// 检测文本中的禁用词
    public func detect(in text: String, scope: TabooScope = .claims) -> [TabooMatch] {
        var matches: [TabooMatch] = []
        let lines = text.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            for rule in rules where rule.appliesTo.contains(scope) || rule.appliesTo.contains(.all) {
                if line.contains(rule.pattern) {
                    matches.append(TabooMatch(rule: rule, line: i + 1, matchedText: line.trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        return matches
    }

    /// 格式化检测报告
    public func report(for text: String, scope: TabooScope = .claims) -> String {
        let matches = detect(in: text, scope: scope)
        if matches.isEmpty { return "✅ 未检测到禁用词" }
        var lines = ["## 禁用词检测报告", "", "| 行 | 禁用词 | 严重度 | 原因 | 建议 |", "|----|--------|--------|------|------|"]
        for m in matches {
            lines.append("| \(m.line) | `\(m.rule.pattern)` | \(m.rule.severity.rawValue) | \(m.rule.reason) | \(m.rule.suggestion) |")
        }
        lines.append(""); lines.append("**共 \(matches.count) 处**")
        return lines.joined(separator: "\n")
    }
}
```

**Tests:**

```swift
// TabooDetectorTests.swift
final class TabooDetectorTests: XCTestCase {
    func testDetect_cleanText_returnsEmpty() async {
        let detector = TabooDetector()
        let text = "一种数据采集装置，其特征在于，包括传感模块"
        let matches = await detector.detect(in: text)
        XCTAssertTrue(matches.isEmpty)
    }
    
    func testDetect_bestPhrase_found() async {
        let detector = TabooDetector()
        let text = "所述温度最好控制在20-30℃之间"
        let matches = await detector.detect(in: text)
        XCTAssertFalse(matches.isEmpty)
        XCTAssertEqual(matches.first?.rule.pattern, "最好")
    }
}
```

- [ ] Write + tests (2 PASS)
- [ ] Commit

### Task 4: 实现 TypedAction（类型化事件系统）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Quality/TypedAction.swift`
- Create: `Tests/YunPatCoreTests/TypedActionTests.swift`

**Code:**

```swift
// Quality/TypedAction.swift
import Foundation

/// 类型化 Action 协议 — 替代 NotificationCenter 字符串
public protocol TypedAction: Sendable {
    associatedtype Payload: Sendable
    var payload: Payload { get }
    static var actionName: String { get }
}

/// Action Dispatcher — 类型安全的事件分发
public actor ActionDispatcher {
    private var handlers: [String: [(Any) async -> Void]] = [:]

    public init() {}

    /// 注册 handler
    public func on<A: TypedAction>(_ actionType: A.Type, handler: @escaping (A.Payload) async -> Void) {
        let key = A.actionName
        if handlers[key] == nil { handlers[key] = [] }
        handlers[key]?.append { payload in
            if let typed = payload as? A.Payload { await handler(typed) }
        }
    }

    /// 分发 action
    public func dispatch<A: TypedAction>(_ action: A) async {
        guard let actionHandlers = handlers[A.actionName] else { return }
        for handler in actionHandlers { await handler(action.payload) }
    }

    /// 移除所有 handler
    public func clear() { handlers.removeAll() }
}

// ── 预定义 Actions ──

public struct NewTabAction: TypedAction {
    public let payload: Void = ()
    public static let actionName = "tab.new"
}

public struct CloseTabAction: TypedAction {
    public let payload: UUID  // tab ID
    public static let actionName = "tab.close"
    public init(tabID: UUID) { self.payload = tabID }
}

public struct SendMessageAction: TypedAction {
    public let payload: String  // 消息文本
    public static let actionName = "chat.send"
    public init(message: String) { self.payload = message }
}

public struct CollaborationApprovedAction: TypedAction {
    public let payload: UUID  // request ID
    public static let actionName = "collaboration.approved"
    public init(requestID: UUID) { self.payload = requestID }
}

public struct CollaborationRejectedAction: TypedAction {
    public let payload: UUID
    public static let actionName = "collaboration.rejected"
    public init(requestID: UUID) { self.payload = requestID }
}
```

**Tests:**

```swift
// TypedActionTests.swift
final class TypedActionTests: XCTestCase {
    func testDispatch_newTab_handlerCalled() async {
        let dispatcher = ActionDispatcher()
        let expectation = XCTestExpectation(description: "handler called")
        await dispatcher.on(NewTabAction.self) { _ in expectation.fulfill() }
        await dispatcher.dispatch(NewTabAction())
        await fulfillment(of: [expectation], timeout: 1)
    }
}
```

- [ ] Write + tests (1 PASS)
- [ ] Commit

### Task 5: 实现 TwoPassDraft（双轮草稿流程）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Quality/TwoPassDraft.swift`

**Code:**

```swift
// Quality/TwoPassDraft.swift
import Foundation

/// 双轮草稿流程 — Pass 1: 初稿 → Pass 2: 诊断 → Pass 3: 修正
public actor TwoPassDraft {
    private let rubric: PatentRubric
    private let tabooDetector: TabooDetector
    private let factEngine: FactMarkerEngine

    public init(rubric: PatentRubric, tabooDetector: TabooDetector = TabooDetector()) {
        self.rubric = rubric; self.tabooDetector = tabooDetector; self.factEngine = FactMarkerEngine()
    }

    /// Phase 1: 提取输入事实标记
    public func extractFacts(from input: String) -> [FactMarker] {
        factEngine.extract(from: input)
    }

    /// Phase 2: 诊断 — 评分 + 禁用词检测 + 事实验证
    public func diagnose(draft: String, inputFacts: [FactMarker], scope: TabooScope = .claims) -> DiagnosisResult {
        let taboos = tabooDetector.detect(in: draft, scope: scope)
        let factResult = factEngine.verify(inputFacts: inputFacts, outputText: draft)
        return DiagnosisResult(taboos: taboos, factVerification: factResult)
    }

    /// 完整流程：输入 → 草稿(由调用方提供) → 诊断 → 判定
    public func evaluate(draft: String, inputFacts: [FactMarker], scope: TabooScope = .claims) -> DraftEvaluation {
        let diagnosis = diagnose(draft: draft, inputFacts: inputFacts, scope: scope)
        // 简单评分：假设每个 rubric criteria 目前由 LLM 填充
        // 实际评分由外部的 EvaluationEngine 负责
        let verdict = diagnosis.verdict
        return DraftEvaluation(diagnosis: diagnosis, verdict: verdict)
    }
}

public struct DiagnosisResult: Sendable {
    public let taboos: [TabooMatch]
    public let factVerification: FactVerificationResult
    public var verdict: RubricVerdict {
        if taboos.contains(where: { $0.rule.severity == .error }) { return .fail(belowMin: ["禁用词"], totalScore: 0) }
        if !factVerification.passed { return .fail(belowMin: ["事实丢失"], totalScore: 0) }
        return .pass
    }
}

public struct DraftEvaluation: Sendable {
    public let diagnosis: DiagnosisResult
    public let verdict: RubricVerdict
    public var summary: String {
        "\(verdict)\n\(diagnosis.factVerification.summary)\n禁用词: \(diagnosis.taboos.count) 处"
    }
}
```

- [ ] Write file, `swift build`
- [ ] Commit

---

## Phase B: 集成升级（Tasks 6-9）

### Task 6: 升级 EvaluationEngine 使用 Rubric + FactMarker + TabooDetector

**Files:**
- Modify: `Packages/YunPatCore/Sources/YunPatCore/Knowledge/EvaluationEngine.swift`

**Change:** 替换简单 pass/fail 为完整的 Rubric 评分 + FactMarker 验证 + TabooDetector 检测。

```swift
// EvaluationEngine — 升级
public actor EvaluationEngine {
    private let rubric = PatentRubric.drafting
    private let factEngine = FactMarkerEngine()
    private let tabooDetector = TabooDetector()
    private let twoPassDraft = TwoPassDraft(rubric: PatentRubric.drafting)

    public func evaluate(execution: ExecutionResult, rules: ApplicableRules, facts: StructuredFacts, caseType: String = "drafting") async -> ReviewResult {
        let outputText = execution.artifacts.joined(separator: "\n")
        let inputFacts = factEngine.extract(from: outputText)

        // 禁用词检测
        let taboos = await tabooDetector.detect(in: outputText, scope: .claims)
        let tabooIssues = taboos.map { Issue(severity: .warning, description: "L\($0.line): `\($0.rule.pattern)` — \($0.rule.reason)") }

        // 事实验证
        let factResult = await factEngine.verify(inputFacts: inputFacts, outputText: outputText)
        let factIssues = factResult.lostFacts.map { Issue(description: "丢失事实: \($0.fact)") }

        let allIssues = tabooIssues + factIssues
        let verdict = allIssues.isEmpty || allIssues.allSatisfy { $0.severity == .warning }

        return ReviewResult(verdict: verdict, issues: allIssues)
    }
}
```

- [ ] Modify, `swift build && swift test --filter EvaluationEngine`
- [ ] Commit

### Task 7: 升级 PatentLoopEngine — Step 3.5 诊断轮

**Files:**
- Modify: `Packages/YunPatCore/Sources/YunPatCore/Loop/PatentLoopEngine.swift`

**Change:** 在 Step 3（规划）和 Step 4（执行）之间插入 Step 3.5（诊断）。

```swift
// PatentLoopEngine — after planning, before execution:
// Step 3.5: 诊断轮（NEW）
state = .running(step: "diagnosing")
let diagnosis = await twoPassDraft.diagnose(
    draft: plan.strategy + plan.steps.map(\.description).joined(separator: "\n"),
    inputFacts: [],
    scope: .claims
)
if case .fail = diagnosis.verdict, flow == .guided {
    return .needsRevision([Issue(description: "诊断不通过: \(diagnosis.factVerification.summary)")])
}

// Step 4: 执行（仅修正诊断中的问题）
state = .running(step: "executing")
```

- [ ] Modify, `swift build && swift test --filter PatentLoopEngineTests`
- [ ] Commit

### Task 8: 升级 ContentView + TabBar 使用 TypedAction

**Files:**
- Modify: `App/Views/ContentView.swift`
- Modify: `App/Views/TabBar.swift`

**Change:** 用 `ActionDispatcher` 替代 `NotificationCenter`。

```swift
// TabBar — replace NotificationCenter with ActionDispatcher
// Before: NotificationCenter.default.post(name: .menuNewTab, object: nil)
// After:  await dispatcher.dispatch(NewTabAction())

// TabManager — replace observer
// Before: NotificationCenter.default.addObserver(forName: .menuNewTab...)
// After:  await dispatcher.on(NewTabAction.self) { _ in self.addTab() }
```

- [ ] Modify, `swift build`
- [ ] Commit

### Task 9: 升级 CollaborationPanel 显示 Rubric 评分

**Files:**
- Modify: `App/Views/CollaborationPanel.swift`

**Change:** 在协作面板中新增「质量评分」视图，展示 Rubric 评分报告。

```swift
// CollaborationPanel — add RubricScoreView
struct RubricScoreView: View {
    let rubric: PatentRubric
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("质量评分: \(rubric.totalScore)/\(rubric.maxPossibleScore)")
                .font(.headline)
            ForEach(rubric.criteria) { c in
                HStack {
                    Text(c.name).font(.caption)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(1...c.maxScore, id: \.self) { i in
                            Circle()
                                .fill(i <= c.score ? Color.accentColor : Color.secondary.opacity(0.2))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            Text(rubric.report()).font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
    }
}
```

---

## Phase C: 验证 + 文档（Tasks 10-12）

### Task 10: 全量回归测试

```bash
cd Packages/YunPatCore && swift test 2>&1 | grep -E "passed|failed|Executed" | tail -5
```

**Expected:** All existing tests pass + 10 new tests

### Task 11: 更新设计文档

- [ ] 在 spec 中新增 §17: Nuo-IDE Quality System Integration

### Task 12: 最终提交

```bash
git add -A
git commit -m "feat: Nuo-IDE quality system — PatentRubric, FactMarker, TabooDetector, TypedAction, TwoPassDraft"
```

---

## 验收标准

- [ ] PatentRubric 3 种预设量表 (drafting/oaResponse/invalidation)
- [ ] FactMarkerEngine 提取 + 验证（丢失检测）
- [ ] TabooDetector 8 条内置规则 + 检测报告
- [ ] TypedAction 5 个预定义 Action + ActionDispatcher
- [ ] TwoPassDraft 双轮草稿流程
- [ ] EvaluationEngine 升级使用全部质量工具
- [ ] PatentLoopEngine Step 3.5 诊断轮
- [ ] CollaborationPanel 显示 Rubric 评分
- [ ] 全部测试通过 (existing + 10 new)
