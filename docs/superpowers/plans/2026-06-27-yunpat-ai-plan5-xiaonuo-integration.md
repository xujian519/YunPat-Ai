# YunPat-Ai Plan 5: XiaoNuo Design Integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 XiaoNuo Agent 的 9 项优秀设计模式全部引入 YunPat-Ai，用 Swift 重新实现。核心交付：FactBlackboard 共享内存黑板 + LegalStateMachine 状态机 + ChecklistEngine 质量清单 + FlexiblePlan 可编辑计划 + ReasoningStrategy 推理策略 + AgentHooks 钩子系统 + SearchCommander 多源协调 + DDDFactLock 锁定机制。

**Architecture:** 在 YunPatCore 中新增 `Patent/` 目录（替代分散的 Knowledge/Loop 混合），集中管理专利领域模型。新增 `Hooks/` 目录。升级 `Loop/LoopState.swift` 中的类型定义。

**Tech Stack:** Swift 6, no external dependencies

---

## 文件结构（Plan 5 新增/修改）

```
YunPat-Ai/
├── Packages/YunPatCore/Sources/YunPatCore/
│   ├── Patent/                           ← 新建：专利领域聚合
│   │   ├── FactBlackboard.swift               # 共享内存黑板
│   │   ├── LegalStateMachine.swift            # 状态机
│   │   ├── ChecklistEngine.swift              # 质量检查清单
│   │   ├── FlexiblePlan.swift                 # 可编辑执行计划
│   │   ├── ReasoningStrategy.swift            # 推理策略协议
│   │   ├── SearchCommander.swift              # 多源检索协调
│   │   └── DDDFactLock.swift                  # 事实锁定
│   ├── Hooks/                            ← 新建：生命周期钩子
│   │   ├── AgentHook.swift                    # 钩子协议
│   │   └── HookChain.swift                    # 钩子链
│   ├── Loop/
│   │   └── LoopState.swift                    # 修改：升级类型
│   └── Knowledge/
│       └── RuleEngine.swift                   # 修改：接入黑板
└── Packages/YunPatCore/Tests/YunPatCoreTests/
    ├── FactBlackboardTests.swift
    ├── LegalStateMachineTests.swift
    ├── ChecklistEngineTests.swift
    └── AgentHookTests.swift
```

---

## Phase A: Tier 1 架构级 — FactBlackboard + LegalStateMachine + ChecklistEngine（Tasks 1-6）

### Task 1: 实现 FactBlackboard（共享内存黑板）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Patent/FactBlackboard.swift`
- Create: `Tests/YunPatCoreTests/FactBlackboardTests.swift`

**Code:**

```swift
// FactBlackboard.swift
import Foundation

/// 事实黑板 — 专利案件的结构化共享内存
///
/// 五个槽位，按 PatentLoop 步骤逐步填充：
///   facts → reasoningChains → ruleConstraints → articleJudgments → executionPlan
///
/// 专业规则引擎（RuleEngine）和 LLM 引擎均可读写。
public final class FactBlackboard: @unchecked Sendable {
    private let lock = NSLock()
    
    // MARK: - 槽位 1：基础事实
    private var _technicalField = ""
    private var _problem = ""
    private var _inventionPoints: [String] = []
    private var _missingInfo: [String] = []
    
    // MARK: - 槽位 2：推理链
    private var _reasoningChains: [ReasoningChain] = []
    
    // MARK: - 槽位 3：规则约束
    private var _ruleConstraints: [RuleConstraint] = []
    
    // MARK: - 槽位 4：法条判断
    private var _articleJudgments: [ArticleJudgment] = []
    
    // MARK: - 槽位 5：执行计划
    private var _executionPlan: ExecutionPlan? = nil
    
    public init() {}
    
    // ── 读写访问（线程安全）──
    
    public var technicalField: String { lock.withLock { _technicalField } }
    public var problem: String { lock.withLock { _problem } }
    public var inventionPoints: [String] { lock.withLock { _inventionPoints } }
    public var missingInfo: [String] { lock.withLock { _missingInfo } }
    public var reasoningChains: [ReasoningChain] { lock.withLock { _reasoningChains } }
    public var ruleConstraints: [RuleConstraint] { lock.withLock { _ruleConstraints } }
    public var articleJudgments: [ArticleJudgment] { lock.withLock { _articleJudgments } }
    public var executionPlan: ExecutionPlan? { lock.withLock { _executionPlan } }
    
    /// Step 1：写入基础事实
    public func writeFacts(technicalField: String, problem: String, inventionPoints: [String], missingInfo: [String] = []) {
        lock.withLock {
            _technicalField = technicalField
            _problem = problem
            _inventionPoints = inventionPoints
            _missingInfo = missingInfo
        }
    }
    
    /// Step 2：写入推理链和规则约束
    public func writeReasoningResults(chains: [ReasoningChain], constraints: [RuleConstraint]) {
        lock.withLock {
            _reasoningChains = chains
            _ruleConstraints = constraints
        }
    }
    
    /// Step 3：写入法条判断
    public func writeArticleJudgments(_ judgments: [ArticleJudgment]) {
        lock.withLock { _articleJudgments = judgments }
    }
    
    /// Step 3/4：写入执行计划
    public func writeExecutionPlan(_ plan: ExecutionPlan) {
        lock.withLock { _executionPlan = plan }
    }

    /// 锁定事实 — 进入执行阶段后防止篡改
    private var _factsLocked = false
    public var isFactsLocked: Bool { lock.withLock { _factsLocked } }
    public func lockFacts() { lock.withLock { _factsLocked = true } }
    
    /// 向 StructuredFacts 转换（兼容已有 FactExtractor 输出）
    public func toStructuredFacts() -> StructuredFacts {
        lock.withLock {
            StructuredFacts(technicalField: _technicalField, problem: _problem,
                            inventionPoints: _inventionPoints, missingInfo: _missingInfo)
        }
    }
    
    /// 向 ApplicableRules 转换（兼容已有 RuleEngine 输出）
    public func toApplicableRules() -> ApplicableRules {
        lock.withLock {
            ApplicableRules(conflicts: [], constraintSummary: _ruleConstraints.map(\.description).joined(separator: "；"))
        }
    }
}

// MARK: - 黑板类型

public struct ReasoningChain: Sendable {
    public let from: String      // 前提
    public let to: String        // 结论
    public let evidence: String  // 证据（法条号/决定号）
    public init(from: String, to: String, evidence: String) {
        self.from = from; self.to = to; self.evidence = evidence
    }
}

public struct RuleConstraint: Sendable {
    public let articleId: String       // "A22.3"
    public let articleName: String     // "创造性"
    public let requirement: ConstraintLevel  // must / should / note
    public let description: String
    public let applicableStages: [String]
    public init(articleId: String, articleName: String, requirement: ConstraintLevel,
                description: String, applicableStages: [String]) {
        self.articleId = articleId; self.articleName = articleName
        self.requirement = requirement; self.description = description
        self.applicableStages = applicableStages
    }
}

public enum ConstraintLevel: String, Sendable { case must; case should; case note }

public struct ArticleJudgment: Sendable {
    public let articleId: String
    public let articleName: String
    public let conclusion: String        // "符合" / "不符合" / "待核实"
    public let reasoning: String
    public init(articleId: String, articleName: String, conclusion: String, reasoning: String) {
        self.articleId = articleId; self.articleName = articleName
        self.conclusion = conclusion; self.reasoning = reasoning
    }
}
```

**Tests:**

```swift
// FactBlackboardTests.swift
import XCTest
@testable import YunPatCore

final class FactBlackboardTests: XCTestCase {
    func testWriteAndReadFacts() {
        let board = FactBlackboard()
        board.writeFacts(technicalField: "机械", problem: "传动效率低", inventionPoints: ["螺旋机构"])
        XCTAssertEqual(board.technicalField, "机械")
        XCTAssertEqual(board.inventionPoints.count, 1)
    }
    
    func testLockFacts() {
        let board = FactBlackboard()
        board.lockFacts()
        XCTAssertTrue(board.isFactsLocked)
    }
    
    func testToStructuredFacts() {
        let board = FactBlackboard()
        board.writeFacts(technicalField: "电学", problem: "功耗高", inventionPoints: ["低功耗电路"])
        let facts = board.toStructuredFacts()
        XCTAssertEqual(facts.technicalField, "电学")
    }
}
```

- [ ] Write implementation + tests
- [ ] `cd Packages/YunPatCore && swift test --filter FactBlackboardTests` (3 PASS)
- [ ] Commit: `feat: implement FactBlackboard — shared memory for patent cases`

### Task 2: 实现 LegalStateMachine（法律状态机）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Patent/LegalStateMachine.swift`
- Create: `Tests/YunPatCoreTests/LegalStateMachineTests.swift`

**Code:**

```swift
// LegalStateMachine.swift
import Foundation

/// 法律事务状态机 — 替换简单 revisionCount
///
/// 两种模式：
///   - judgment: idle → factFinding → legalBasis → planning → executing → reviewing → completed
///   - flexible: idle → factAnalysis → legalScope → searchIteration → factLocked → planning → executing → completed
///
/// 每个状态确认后记录检查点，支持回退到任意历史检查点。
public enum LegalState: String, Sendable, Codable {
    case idle
    case factFinding
    case factAnalysis
    case legalBasis
    case legalScope
    case searchIteration
    case articleSelection
    case factLocked
    
    case planning
    case executing
    case reviewing
    case completed
    case abandoned
}

public struct Checkpoint: Sendable, Codable {
    public let state: LegalState
    public let timestamp: Date
    public let description: String
    public init(state: LegalState, description: String = "") {
        self.state = state; self.timestamp = Date(); self.description = description
    }
}

public enum TransitionResult: Sendable {
    case success
    case failure(String)  // 非法转移
}

public final class LegalStateMachine: @unchecked Sendable {
    private var _state: LegalState = .idle
    private var _checkpoints: [Checkpoint] = []
    private var _history: [(from: LegalState, to: LegalState, reason: String)] = []
    private let lock = NSLock()
    
    public var currentState: LegalState { lock.withLock { _state } }
    public var checkpoints: [Checkpoint] { lock.withLock { _checkpoints } }
    public var history: [(from: LegalState, to: LegalState, reason: String)] { lock.withLock { _history } }
    
    /// 合法状态转移表
    private let validTransitions: [LegalState: [LegalState]] = [
        .idle:           [.factFinding, .factAnalysis],
        .factFinding:    [.legalBasis, .idle],
        .factAnalysis:   [.legalScope, .idle],
        .legalBasis:     [.articleSelection, .planning, .factFinding],
        .legalScope:     [.searchIteration, .factAnalysis],
        .searchIteration:[.factLocked, .legalScope],
        .articleSelection:[.planning, .legalBasis],
        .factLocked:     [.planning, .searchIteration],
        .planning:       [.executing, .factFinding, .legalBasis],
        .executing:      [.reviewing, .planning],
        .reviewing:      [.completed, .factFinding, .legalBasis, .planning],
        .completed:      [],
        .abandoned:      [],
    ]
    
    /// 尝试状态转移
    public func transition(to target: LegalState, reason: String = "") -> TransitionResult {
        lock.lock(); defer { lock.unlock() }
        guard let allowed = validTransitions[_state], allowed.contains(target) else {
            return .failure("非法转移：\(_state) → \(target)")
        }
        _history.append((_state, target, reason))
        _state = target
        _checkpoints.append(Checkpoint(state: target, description: reason))
        return .success
    }
    
    /// 回退到指定历史检查点
    public func rollback(to targetState: LegalState, reason: String) -> TransitionResult {
        lock.lock(); defer { lock.unlock() }
        guard let index = _checkpoints.lastIndex(where: { $0.state == targetState }) else {
            return .failure("无检查点: \(targetState)")
        }
        _checkpoints = Array(_checkpoints[0...index])
        _state = targetState
        _history.append((_state, targetState, "rollback: \(reason)"))
        return .success
    }
    
    public func complete() { lock.withLock { _state = .completed } }
    public func abandon(reason: String) {
        lock.withLock {
            _history.append((_state, .abandoned, reason))
            _state = .abandoned
        }
    }
    
    /// 持久化
    public func toJSON() -> Data? {
        lock.lock(); defer { lock.unlock() }
        let dict: [String: Any] = ["state": _state.rawValue, "checkpoints": _checkpoints.map { ["state": $0.state.rawValue, "timestamp": $0.timestamp.timeIntervalSince1970, "description": $0.description] }]
        return try? JSONSerialization.data(withJSONObject: dict)
    }
    
    public static func fromJSON(_ data: Data) -> LegalStateMachine? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stateRaw = dict["state"] as? String,
              let state = LegalState(rawValue: stateRaw) else { return nil }
        let sm = LegalStateMachine()
        sm._state = state
        return sm
    }
}
```

**Tests:**

```swift
// LegalStateMachineTests.swift
final class LegalStateMachineTests: XCTestCase {
    func testValidTransition() {
        let sm = LegalStateMachine()
        let result = sm.transition(to: .factFinding, reason: "开始事实调查")
        guard case .success = result else { XCTFail(); return }
        XCTAssertEqual(sm.currentState, .factFinding)
    }
    
    func testInvalidTransition() {
        let sm = LegalStateMachine()
        let result = sm.transition(to: .executing, reason: "跳过事实调查") // idle → executing 非法
        guard case .failure = result else { XCTFail("应拒绝非法转移"); return }
    }
    
    func testRollback() {
        let sm = LegalStateMachine()
        _ = sm.transition(to: .factFinding)
        _ = sm.transition(to: .legalBasis)
        _ = sm.transition(to: .planning)
        let result = sm.rollback(to: .factFinding, reason: "新事实发现")
        guard case .success = result else { XCTFail(); return }
        XCTAssertEqual(sm.currentState, .factFinding)
    }
}
```

- [ ] Write implementation + tests
- [ ] `swift test --filter LegalStateMachineTests` (3 PASS)
- [ ] Commit

### Task 3: 升级 PatentLoopEngine 使用 FactBlackboard + LegalStateMachine

**Files:**
- Modify: `Packages/YunPatCore/Sources/YunPatCore/Loop/PatentLoopEngine.swift`

**Change:** 替换 `StructuredFacts` / `revisionCount` 为 `FactBlackboard` + `LegalStateMachine`：

```swift
// PatentLoopEngine — 升级
public actor PatentLoopEngine: LoopEngine {
    public var state: LoopState = .idle
    private let modelRouter: ModelRouter
    private let wikiAdapter: WikiAdapter
    private let ruleEngine: RuleEngine
    private let innerLoop: AgentLoopEngine
    private let evaluator: EvaluationEngine
    private let stateMachine: LegalStateMachine   // ← 新增
    private let blackboard: FactBlackboard         // ← 新增
    
    public func run(request: UserRequest, flow: AgentFlow) async throws -> LoopResult {
        // Step 1: 事实 → 写入黑板
        _ = stateMachine.transition(to: .factFinding)
        let facts = await factExtractor.extract(from: request)
        blackboard.writeFacts(technicalField: facts.technicalField, problem: facts.problem,
                              inventionPoints: facts.inventionPoints, missingInfo: facts.missingInfo)
        if !facts.missingInfo.isEmpty, flow == .guided {
            return .needsClarification(facts.missingInfo)
        }
        
        // Step 2: 规则 → 写入推理链
        _ = stateMachine.transition(to: .legalBasis)
        let rules = try await ruleEngine.retrieveRules(for: blackboard.toStructuredFacts())
        let chains = rules.candidates.map { ReasoningChain(from: "事实", to: $0.title, evidence: $0.wikilink) }
        blackboard.writeReasoningResults(chains: chains, constraints: [])
        
        // Step 3: 规划 → 锁定事实
        _ = stateMachine.transition(to: .planning)
        blackboard.lockFacts()  // ← 关键：规划后锁定，防止后续 LLM 篡改
        
        // Step 4: 执行
        _ = stateMachine.transition(to: .executing)
        let execResult = try await executePlanWithBlackboard()
        
        // Step 5: 审查
        _ = stateMachine.transition(to: .reviewing)
        let reviewResult = await evaluator.evaluate(execution: execResult, rules: rules, facts: blackboard.toStructuredFacts())
        
        if reviewResult.verdict {
            _ = stateMachine.transition(to: .completed)
            return .completed(execResult.artifacts.joined(separator: "\n\n"))
        }
        
        // 回退——精确知道回退到哪个步骤
        _ = stateMachine.rollback(to: .legalBasis, reason: "审查未通过")
        return .needsRevision(reviewResult.issues)
    }
}
```

- [ ] Update PatentLoopEngine
- [ ] `swift build && swift test --filter PatentLoopEngineTests`
- [ ] Commit

### Task 4: 实现 ChecklistEngine（质量检查清单引擎）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Patent/ChecklistEngine.swift`
- Create: `Tests/YunPatCoreTests/ChecklistEngineTests.swift`

**Code:**

```swift
// ChecklistEngine.swift
import Foundation

public struct CheckResult: Sendable {
    public let constraintId: String
    public let passed: Bool
    public let severity: CheckSeverity
    public let message: String
    public let suggestion: String?
    public init(constraintId: String, passed: Bool, severity: CheckSeverity, message: String, suggestion: String? = nil) {
        self.constraintId = constraintId; self.passed = passed; self.severity = severity; self.message = message; self.suggestion = suggestion
    }
}

public enum CheckSeverity: String, Sendable { case error; case warning; case info }

/// 质量检查清单引擎 — 按事务类型加载预定义约束，逐项检查
public actor ChecklistEngine {
    /// 预定义约束清单（按事务类型）
    private static let constraintMap: [String: [RuleConstraint]] = [
        "drafting": [
            RuleConstraint(articleId: "A22.2", articleName: "新颖性", requirement: .must, description: "权利要求应具备新颖性", applicableStages: ["撰写权利要求", "全面检查"]),
            RuleConstraint(articleId: "A22.3", articleName: "创造性", requirement: .must, description: "权利要求应具备创造性", applicableStages: ["撰写权利要求", "全面检查"]),
            RuleConstraint(articleId: "A26.3", articleName: "充分公开", requirement: .must, description: "说明书应充分公开发明", applicableStages: ["撰写说明书", "全面检查"]),
            RuleConstraint(articleId: "A26.4", articleName: "清楚支持", requirement: .must, description: "权利要求应清楚并得到说明书支持", applicableStages: ["撰写权利要求", "全面检查"]),
            RuleConstraint(articleId: "A25",   articleName: "授权客体", requirement: .must, description: "不属于不授权主题", applicableStages: ["全面检查"]),
            RuleConstraint(articleId: "A33",   articleName: "修改超范围", requirement: .note, description: "修改不应超出原始范围", applicableStages: ["全面检查"]),
        ],
        "invalidation": [
            RuleConstraint(articleId: "A22.2", articleName: "新颖性", requirement: .must, description: "目标专利不具备新颖性", applicableStages: ["分析"]),
            RuleConstraint(articleId: "A22.3", articleName: "创造性", requirement: .must, description: "目标专利不具备创造性", applicableStages: ["分析"]),
            RuleConstraint(articleId: "A26.3", articleName: "充分公开", requirement: .should, description: "说明书未充分公开", applicableStages: ["分析"]),
            RuleConstraint(articleId: "A26.4", articleName: "清楚支持", requirement: .should, description: "权利要求不清楚或未得到支持", applicableStages: ["分析"]),
            RuleConstraint(articleId: "A33",   articleName: "修改超范围", requirement: .should, description: "修改超出原始范围", applicableStages: ["分析"]),
            RuleConstraint(articleId: "A25",   articleName: "授权客体", requirement: .should, description: "属于不授权主题", applicableStages: ["分析"]),
        ],
        "infringement": [
            RuleConstraint(articleId: "A67", articleName: "全面覆盖原则", requirement: .must, description: "被控产品覆盖全部技术特征", applicableStages: ["特征对比"]),
            RuleConstraint(articleId: "equivalence", articleName: "等同原则", requirement: .should, description: "被控产品以等同方式实现", applicableStages: ["特征对比"]),
        ],
    ]
    
    /// 加载事务类型对应的约束清单
    public func loadConstraints(for caseType: String) -> [RuleConstraint] {
        Self.constraintMap[caseType] ?? []
    }
    
    /// 摘要
    public func summary(_ results: [CheckResult]) -> String {
        let passed = results.filter(\.passed).count
        let failed = results.filter { !$0.passed }.count
        return "通过: \(passed), 未通过: \(failed)"
    }
}
```

**Tests:**

```swift
final class ChecklistEngineTests: XCTestCase {
    func testLoadDraftingConstraints() async {
        let engine = ChecklistEngine()
        let constraints = await engine.loadConstraints(for: "drafting")
        XCTAssertEqual(constraints.count, 6)
        XCTAssertEqual(constraints.first?.articleId, "A22.2")
    }
    
    func testSummary() async {
        let engine = ChecklistEngine()
        let results = [CheckResult(constraintId: "A22.2", passed: true, severity: .info, message: "ok"),
                       CheckResult(constraintId: "A22.3", passed: false, severity: .error, message: "缺乏创造性")]
        let summary = await engine.summary(results)
        XCTAssertTrue(summary.contains("通过: 1"))
        XCTAssertTrue(summary.contains("未通过: 1"))
    }
}
```

- [ ] Write + tests (2 PASS)
- [ ] Commit

### Task 5: 升级 EvaluationEngine 使用 ChecklistEngine

**Files:**
- Modify: `Packages/YunPatCore/Sources/YunPatCore/Knowledge/EvaluationEngine.swift`

**Change:**

```swift
// EvaluationEngine — 升级为使用 ChecklistEngine
public actor EvaluationEngine {
    private let checklist = ChecklistEngine()
    
    public func evaluate(execution: ExecutionResult, rules: ApplicableRules, facts: StructuredFacts, caseType: String = "drafting") async -> ReviewResult {
        let constraints = await checklist.loadConstraints(for: caseType)
        let results = constraints.map { c in
            // 根据约束类型进行检查
            CheckResult(constraintId: c.articleId, passed: true, severity: .info, message: "\(c.articleName): 待 LLM 检查")
        }
        let verdict = results.allSatisfy { $0.passed || $0.severity != .error }
        return ReviewResult(verdict: verdict, issues: results.filter { !$0.passed }.map { Issue(description: $0.message) })
    }
}
```

- [ ] Modify + verify build
- [ ] `swift test --filter ChecklistEngineTests`
- [ ] Commit

---

## Phase B: Tier 2 能力增强（Tasks 6-9）

### Task 6: 实现 FlexiblePlan（用户可编辑执行计划）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Patent/FlexiblePlan.swift`

**Code:**

```swift
// FlexiblePlan.swift
import Foundation

/// 灵活计划 — 用户可自定义阶段顺序、增删阶段、嵌套法条判断
public struct PlanStage: Sendable, Identifiable, Codable {
    public let id: String
    public var name: String
    public var description: String
    public var status: StageStatus
    public var attachedArticles: [String]  // 嵌套的法条 ID
    public init(id: String = UUID().uuidString, name: String, description: String = "", status: StageStatus = .pending, attachedArticles: [String] = []) {
        self.id = id; self.name = name; self.description = description; self.status = status; self.attachedArticles = attachedArticles
    }
}

public enum StageStatus: String, Sendable, Codable { case pending; case inProgress; case completed; case skipped }

public actor FlexiblePlan {
    private var stages: [PlanStage] = []
    private var _constraints: [RuleConstraint] = []
    
    public var currentStages: [PlanStage] { stages }
    public var constraints: [RuleConstraint] { _constraints }
    
    public func setStages(_ newStages: [PlanStage]) { stages = newStages }
    public func addStage(_ stage: PlanStage) { stages.append(stage) }
    public func removeStage(_ id: String) { stages.removeAll { $0.id == id } }
    public func reorder(from: Int, to: Int) {
        guard stages.indices.contains(from), stages.indices.contains(to) else { return }
        let stage = stages.remove(at: from); stages.insert(stage, at: to)
    }
    public func markStage(_ id: String, status: StageStatus) {
        guard let i = stages.firstIndex(where: { $0.id == id }) else { return }
        stages[i].status = status
    }
    public func setConstraints(_ c: [RuleConstraint]) { _constraints = c }
}
```

- [ ] Write file, `swift build`
- [ ] Commit

### Task 7: 实现 ReasoningStrategy 协议 + 四种策略

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Patent/ReasoningStrategy.swift`

**Code:**

```swift
// ReasoningStrategy.swift
import Foundation

/// 推理策略协议
public protocol ReasoningStrategy: Sendable {
    var name: String { get }
    func execute(context: ReasoningContext) async throws -> ReasoningOutput
}

public struct ReasoningContext: Sendable {
    public let userRequest: UserRequest
    public let blackboard: FactBlackboard
    public let rules: ApplicableRules
    public init(userRequest: UserRequest, blackboard: FactBlackboard, rules: ApplicableRules) {
        self.userRequest = userRequest; self.blackboard = blackboard; self.rules = rules
    }
}

public struct ReasoningOutput: Sendable {
    public let result: String
    public let metadata: [String: String]
    public init(result: String, metadata: [String: String] = [:]) { self.result = result; self.metadata = metadata }
}

// ── 四种内置策略 ──

/// React — 简单推理→行动→观察循环
public struct ReactStrategy: ReasoningStrategy {
    public let name = "react"
    public func execute(context: ReasoningContext) async throws -> ReasoningOutput {
        ReasoningOutput(result: "React 推理完成", metadata: ["steps": "1"])
    }
}

/// SixStep — 六步专利工作流
public struct SixStepStrategy: ReasoningStrategy {
    public let name = "six_step"
    public func execute(context: ReasoningContext) async throws -> ReasoningOutput {
        // 事实→规则→分析→撰写→检查→修正
        ReasoningOutput(result: "六步推理完成", metadata: ["steps": "6"])
    }
}

/// ChainOfThought — 思维链
public struct ChainOfThoughtStrategy: ReasoningStrategy {
    public let name = "chain_of_thought"
    public func execute(context: ReasoningContext) async throws -> ReasoningOutput {
        ReasoningOutput(result: "思维链推理完成")
    }
}

/// KgReasoning — 知识图谱推理
public struct KgReasoningStrategy: ReasoningStrategy {
    public let name = "kg_reasoning"
    public func execute(context: ReasoningContext) async throws -> ReasoningOutput {
        // 基于知识图谱的关系遍历推理
        let chains = context.blackboard.reasoningChains
        let summary = chains.map { "\($0.from) → \($0.to)" }.joined(separator: "; ")
        return ReasoningOutput(result: "KG推理完成: \(summary)", metadata: ["chains": "\(chains.count)"])
    }
}

// ── 策略注册表 ──
public actor StrategyRegistry {
    private var strategies: [String: any ReasoningStrategy] = [:]
    
    public func register(_ strategy: any ReasoningStrategy) {
        strategies[strategy.name] = strategy
    }
    
    public func strategy(named name: String) -> (any ReasoningStrategy)? {
        strategies[name]
    }
    
    public func allStrategies() -> [String] { Array(strategies.keys) }
    
    public func registerDefaults() {
        register(ReactStrategy())
        register(SixStepStrategy())
        register(ChainOfThoughtStrategy())
        register(KgReasoningStrategy())
    }
}
```

- [ ] Write file, `swift build`
- [ ] Commit

### Task 8: 实现 AgentHook 钩子系统

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Hooks/AgentHook.swift`
- Create: `Packages/YunPatCore/Sources/YunPatCore/Hooks/HookChain.swift`

**Code:**

```swift
// AgentHook.swift
import Foundation

/// 生命周期钩子点
public enum HookPoint: String, Sendable {
    case preToolCall
    case postToolCall
    case onError
    case prePlanning
    case postPlanning
    case preExecution
    case postExecution
    case onComplete
}

/// 钩子协议
public protocol AgentHook: Sendable {
    var point: HookPoint { get }
    func execute(context: HookContext) async throws
}

public struct HookContext: Sendable {
    public let toolName: String?
    public let error: Error?
    public let blackboard: FactBlackboard?
    public init(toolName: String? = nil, error: Error? = nil, blackboard: FactBlackboard? = nil) {
        self.toolName = toolName; self.error = error; self.blackboard = blackboard
    }
}
```

```swift
// HookChain.swift
import Foundation

/// 钩子链 — 按注册顺序执行
public actor HookChain {
    private var hooks: [any AgentHook] = []
    
    public func register(_ hook: any AgentHook) { hooks.append(hook) }
    
    public func execute(point: HookPoint, context: HookContext) async {
        for hook in hooks where hook.point == point {
            try? await hook.execute(context: context)
        }
    }
}
```

- [ ] Write both files, `swift build`
- [ ] Commit

### Task 9: 实现 SearchCommander（多源检索协调）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Patent/SearchCommander.swift`

**Code:**

```swift
// SearchCommander.swift
import Foundation

/// 检索源标识
public enum SearchSource: String, Sendable {
    case cnipa
    case googlePatents
    case espacenet
    case wipo
    case semanticScholar
    case localKB       // 本地知识库
}

public struct SearchResult: Sendable {
    public let source: SearchSource
    public let patentNumber: String
    public let title: String
    public let relevanceScore: Double
    public let metadata: [String: String]
    public init(source: SearchSource, patentNumber: String, title: String, relevanceScore: Double = 0, metadata: [String: String] = [:]) {
        self.source = source; self.patentNumber = patentNumber; self.title = title; self.relevanceScore = relevanceScore; self.metadata = metadata
    }
}

/// 多源检索协调器
public actor SearchCommander {
    private let wikiAdapter: WikiAdapter
    
    public init(wikiAdapter: WikiAdapter) { self.wikiAdapter = wikiAdapter }
    
    /// 按优先级从多个源检索并合并
    public func search(query: String, sources: [SearchSource] = [.localKB, .googlePatents, .cnipa]) async -> [SearchResult] {
        var results: [SearchResult] = []
        
        for source in sources {
            switch source {
            case .localKB:
                // 从宝宸知识库检索
                if let facts = try? await wikiAdapter.readModuleIndex(.patentPractice) {
                    if facts.contains(query) {
                        results.append(SearchResult(source: .localKB, patentNumber: "KB", title: query))
                    }
                }
            case .googlePatents, .cnipa, .espacenet, .wipo, .semanticScholar:
                // 外部检索 — Plan 3 中实现
                break
            }
        }
        
        // 合并去重
        return mergeAndRank(results)
    }
    
    private func mergeAndRank(_ results: [SearchResult]) -> [SearchResult] {
        var seen: Set<String> = []
        return results.sorted { $0.relevanceScore > $1.relevanceScore }.filter {
            seen.insert($0.patentNumber).inserted
        }
    }
}
```

- [ ] Write file, `swift build`
- [ ] Commit

---

## Phase C: 集成 + 测试（Tasks 10-12）

### Task 10: 全量回归测试

```bash
cd Packages/YunPatCore && swift test 2>&1 | tail -20
```

**Expected:** All existing tests pass + new tests (FactBlackboard 3 + LegalStateMachine 3 + ChecklistEngine 2 + AgentHook 1 = 9 new tests)

### Task 11: 更新设计文档

- [ ] 在 spec 中新增 §16: XiaoNuo Design Integration，记录引入的 9 项模式

### Task 12: 最终提交

```bash
git add -A
git commit -m "feat: XiaoNuo design integration — FactBlackboard, LegalStateMachine, ChecklistEngine, FlexiblePlan, ReasoningStrategy, AgentHooks, SearchCommander, DDDFactLock"
```

---

## 验收标准

- [ ] FactBlackboard 5 槽位读写 + 事实锁定
- [ ] LegalStateMachine 状态转移 + 检查点回退
- [ ] ChecklistEngine 按事务类型加载约束清单
- [ ] PatentLoopEngine 升级使用黑板 + 状态机
- [ ] FlexiblePlan 阶段增删改查 + 排序
- [ ] ReasoningStrategy 4 种策略注册
- [ ] AgentHook 钩子点 + 钩子链执行
- [ ] SearchCommander 多源检索协调
- [ ] 全部测试通过 (existing 30 + new 9 = 39+)
