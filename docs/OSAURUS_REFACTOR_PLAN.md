# YunPat-Ai 重构优化方案（基于 Osaurus 设计引入）

> 配套文档：`docs/OSAURUS_INTRODUCTION_ANALYSIS.md`（设计调研）
> 制定日期：2026-06-28
> 目标：将 12 项 Osaurus 优秀设计逐项落地为可执行的重构方案，含接口设计、迁移步骤、风险回退、验收检查清单，并汇总为全局任务清单。
> 约束：所有方案贴合本项目现有命名与代码（`PatentLoopEngine` / `ToolDispatch` / `HooksService` / `LoopResult` / `MemoryEngine` / `CapabilityRegistry` / `ContextEngine` 等），标注与现有代码的衔接点。

---

## 现状关键发现（影响方案设计）

| 已有资产 | 位置 | 可复用为 |
|---|---|---|
| `task_complete` / `ask_user` 工具 stub | `ToolDispatch.swift:121-122` | complete/clarify 的雏形，需补 summary 校验 + 拦截 |
| `HooksService` + `dispatchWithHooks` | `ToolDispatch.swift:190` | 并行批处理的两阶段审批基础 |
| `readOnlyTools` 集合 | `ToolDispatch.swift:92` | 并行批处理 + intra-batch dedupe 的只读判定 |
| `LoopResult` 五态 | `LoopState.swift:46` | 退出分类（需补 `endedBySurface`/`overBudget`） |
| `LoopGuard`/`StuckGuard` | `StuckGuard.swift` | Harness Task State 的雏形（需结构化升级） |
| `MemoryEngine` 5 层 + 文件 JSON 存储 | `MemoryEngine.swift` | 领域模型保留，工程化重写 |
| `CapabilityRegistry` + `ToolDefinition` | `Capability/` | frozen manifest 的数据基础 |

---

# 第一部分：逐项重构方案

## 方案 1：单一 Loop 驱动 + Policy 钩子（P0）

### 1.1 现状
- `PatentLoopEngine.run` 内部嵌套调用 `innerLoop.run`（`AgentLoopEngine`），是嵌套而非共享驱动。
- `SubAgentEngine` 三路并行是独立第三套逻辑。
- 预算记账、去重、退出分类散落在各 Loop，未来 Plugin/HTTP/Schedule 入口需重写。

### 1.2 目标设计

新增统一驱动 `PatentToolLoop`（actor），所有 surface（Chat/Patent/SubAgent/未来的 HTTP/Plugin）共用：

```swift
// Loop/PatentToolLoop.swift (新增)
public actor PatentToolLoop {
    public func run(
        request: UserRequest,
        policy: PatentLoopPolicy,
        hooks: PatentLoopHooks
    ) async -> LoopExit
}

/// 退出分类（6 种，对齐 osaurus）
public enum LoopExit: Sendable {
    case finalResponse(String)
    case iterationCapReached(String)   // 末轮工具仍执行
    case toolRejected(String)
    case cancelled
    case endedBySurface(String)        // complete/clarify 拦截
    case overBudget(String)            // 压缩后仍放不下
}

/// 命名旋钮（替代 fork）
public struct PatentLoopPolicy: Sendable {
    public let maxIterations: Int
    public let stopOnToolRejection: Bool
    public let dedupeNoticeEnabled: Bool
    public let budgetWarningThreshold: Int  // 默认 3
    public init(maxIterations: Int = 20,
                stopOnToolRejection: Bool = true,
                dedupeNoticeEnabled: Bool = true,
                budgetWarningThreshold: Int = 3) { ... }
}

/// surface 提供的回调（Chat / HTTP / Plugin 各自实现）
public struct PatentLoopHooks: Sendable {
    public let buildMessages: @Sendable () async -> [Message]
    public let modelStep: @Sendable ([Message], [ToolSpec]) async throws -> ModelStepResult
    public let executeTool: @Sendable (ToolCall) async -> ToolEnvelope
    public let executeBatch: @Sendable ([ToolCall]) async -> [ToolEnvelope]
    public let onTodoUpdate: @Sendable (String) async -> Void
    public let onClarify: @Sendable (ClarifyRequest) async -> String  // 返回用户答案
}
```

PatentLoop 的"五步"不再是 `run()` 内硬编码序列，而是 **policy 的阶段化**：`factExtract → ruleRetrieve → plan → execute → review` 各阶段是 hooks 的不同配置，guided flow 在 factExtract 后可 `endedBySurface`。

### 1.3 实施步骤
1. 新增 `PatentToolLoop.swift` + `LoopExit`/`PatentLoopPolicy`/`PatentLoopHooks`（纯新增，不改现有）。
2. 在 `PatentToolLoop` 内实现迭代主循环：预算记账（接 `AgentLoopBudget`，见方案 3）、工具批处理（方案 5）、去重 nudge（方案 4）、退出分类。
3. 将 `AgentLoopEngine` 改造为 `PatentToolLoop` 的 Chat surface adapter（提供 hooks），保留其公共 API 向后兼容（内部委托）。
4. 将 `PatentLoopEngine` 改造为 surface adapter，五步流程映射为 hooks 阶段。
5. 将 `SubAgentEngine.spawnBatch` 改为每个子任务一个 `PatentToolLoop.run`。
6. 旧的嵌套 `innerLoop.run` 调用删除。

### 1.4 风险与回退
- **风险**：改动面大，可能破坏现有测试（`PatentLoopEngineTests`/`AgentLoopEngineTests`）。
- **回退**：分阶段合并——先新增 `PatentToolLoop` 并让 `AgentLoopEngine` 委托（旧 API 不变），验证后再迁移 `PatentLoopEngine`，最后迁移 `SubAgentEngine`。每阶段独立可发布。

### 1.5 验收检查清单
- [ ] `PatentToolLoop` 单一驱动存在，无 `innerLoop.run` 嵌套。
- [ ] Chat/Patent/SubAgent 三个 surface 共用同一 driver，仅 hooks/policy 不同。
- [ ] `LoopExit` 六态全覆盖，`PatentLoopEngineTests`/`AgentLoopEngineTests` 全绿。
- [ ] 新增 `PatentToolLoopTests`：验证迭代上限、工具拒绝、endedBySurface、overBudget 四条退出路径。
- [ ] 三个 surface 的预算/去重/退出逻辑无重复代码。

---

## 方案 2：三层 Loop 工具（todo/complete/clarify）+ 拦截（P1）

### 2.1 现状
- `task_complete`（`ToolDispatch.swift:137`）和 `ask_user`（:141）是 stub，无 summary 校验、无拦截、返回散文本。
- `PatentLoopEngine` guided flow 用 `return .needsClarification` 硬编码。
- 无 todo 实时 checklist。

### 2.2 目标设计

```swift
// Tools/AgentLoopTools.swift (新增)
public enum AgentLoopTools {
    public static let todo = ToolSpec(name: "todo", ...)
    public static let complete = ToolSpec(name: "complete", ...)
    public static let clarify = ToolSpec(name: "clarify", ...)

    /// complete 的 summary 校验 — 拒绝占位符，要求 ≥30 字实质描述
    public static func validate(summary: String) -> Bool {
        let placeholders = ["done","ok","完成","已完成","好了","looks good","complete","finished"]
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 30 { return false }
        if placeholders.contains(trimmed.lowercased()) { return false }
        return true
    }
}

public struct ClarifyRequest: Sendable {
    public let question: String
    public let options: [String]       // ≤6
    public let allowMultiple: Bool
}

/// 拦截器：在 ToolRegistry.execute 返回后判断是否结束/暂停 Loop
public struct LoopIntercept: Sendable {
    public let endRun: Bool            // complete → true
    public let pauseRun: Bool          // clarify → true
    public let validatedSummary: String?
}
```

工具表注册（替换现有 `task_complete`/`ask_user` stub）：
- `todo(markdown)` → 整表替换 checklist，回调 `hooks.onTodoUpdate`
- `complete(summary)` → 校验失败返回 `ToolEnvelope.error`（落回模型重试），成功触发拦截 `endedBySurface`
- `clarify(question, options?, allowMultiple?)` → 触发拦截，`hooks.onClarify` 拿用户答案作为下一轮 user turn

拦截规则：`!ToolEnvelope.isError(resultText)` 才生效；批内含 intercept 强制串行。

### 2.3 实施步骤
1. 新增 `AgentLoopTools.swift` + `validate(summary:)` + `ClarifyRequest`/`LoopIntercept`。
2. 在 `ToolDispatch` 用 `todo`/`complete`/`clarify` 替换 `task_complete`/`ask_user` stub（保留旧名做别名兼容）。
3. 在 `PatentToolLoop` 主循环内加 post-execute 拦截分支（方案 1 的 hooks 已预留）。
4. `ContextEngine`/system prompt 注入"Agent Loop 指引"块，告诉模型何时调哪个。
5. UI 层：Chat view 加 todo checklist 实时渲染 + clarify 底部 overlay（单槽 `PromptQueue`，不与 secret prompt 叠加）。

### 2.4 风险与回退
- **风险**：旧 `task_complete`/`ask_user` 调用方需迁移。
- **回退**：保留旧工具名做内部转发（`task_complete` → `complete`），一个版本后再删。

### 2.5 验收检查清单
- [ ] `validate(summary:))` 单测：`done`/`ok`/`已完成`/短于 30 字均返回 false。
- [ ] `complete` 校验失败返回 error envelope，Loop 继续（非 endedBySurface）。
- [ ] `complete` 校验成功 → `LoopExit.endedBySurface`。
- [ ] `clarify` 触发 `pauseRun`，用户答案作为下一轮 user turn 恢复 Loop。
- [ ] 批内含 `complete`/`clarify` 强制串行，停在首个 endRun。
- [ ] UI 渲染 todo checklist + clarify overlay。
- [ ] 新增 `AgentLoopToolsTests`。

---

## 方案 3：KV-stable Context 压缩（P0）

### 3.1 现状
- `ContextEngine.buildPrompt`（`ContextEngine.swift:34`）超预算时 `String(full.prefix(maxTokenBudget*4))`——直接砍尾巴，破坏整个 prefix cache。
- token 估算 `full.count / 4`（中文专利文书严重低估）。
- 无 watermark、无 byte-stable 概念。

### 3.2 目标设计

```swift
// Context/CompactionWatermark.swift (新增)
public actor CompactionWatermark {
    /// 已摘要的 tool result：id → 固定摘要文本（永不重写）
    private var summarizedResults: [String: String] = [:]
    /// 已 drop 的消息 id 集合（永不复活）
    private var droppedMessageIds: Set<UUID> = []
    /// trim note（count-free，字节固定）
    static let trimNote = "[Note: Earlier messages were trimmed…]"

    /// 压缩主入口 — 保证渲染 prefix 跨迭代 byte-stable
    public func compact(history: [Message], budget: TokenBudget) -> [Message]
}

// Context/ContextBudget.swift (新增)
public struct TokenBudget: Sendable {
    public let window: Int               // 模型上下文窗口
    public let effectiveBudget: Int      // window × 0.85
    public let reservedSystem: Int
    public let reservedTools: Int
    public let reservedResponse: Int     // max_tokens
    public var availableForHistory: Int { effectiveBudget - reservedSystem - reservedTools - reservedResponse }
}

/// token 估算 — 中文友好
public enum TokenEstimator {
    public static func estimate(_ text: String, provider: ModelProvider) -> Int {
        switch provider {
        case .deepseek, .glm, .openaiCompat:
            return text.count / 2          // 中文 ~1.5-2 char/token
        default:
            return text.count / 4
        }
    }
}
```

压缩规则（对齐 osaurus）：
1. 先 trim history（notice 无关）。
2. 已发送 verbatim 消息老化时**只 drop 不重新摘要**。
3. 一旦 tool result 被摘要，**逐字节重放**。
4. trim note count-free。
5. 受保护区：首条消息（原始任务）+ 最近 3 个 turn-pair。
6. 受保护区 + tail 仍超 → `LoopExit.overBudget`。

### 3.3 实施步骤
1. 新增 `TokenEstimator`，替换 `ContextEngine` 内 `count/4`。
2. 新增 `ContextBudget` + `TokenBudget`，接入 `ContextEngine`。
3. 新增 `CompactionWatermark`，替换 `String.prefix` 截断。
4. `PatentToolLoop`（方案 1）每轮调用 `compact(history:budget:)`，UI context chip 共用同一 budget 计算（UI 与 runtime 永不矛盾）。
5. overBudget 信号接入 `LoopExit.overBudget`。

### 3.4 风险与回退
- **风险**：watermark 状态需随 session 生命周期管理；中英文混合 token 估算仍不精确。
- **回退**：`TokenEstimator` 先用经验值（char/2 for CJK），后续可接 provider tokenizer 精确化；watermark 可按 session 重置。

### 3.5 验收检查清单
- [ ] `TokenEstimator` 中文估算 ≥ `count/2`。
- [ ] `CompactionWatermark` 同一 tool result 摘要跨轮 byte-identical（字节级断言）。
- [ ] 已 drop 消息不复活。
- [ ] trim note 字节固定（多次 drop 不改其字节）。
- [ ] 受保护区（首消息 + 最近 3 turn-pair）不被压缩。
- [ ] 受保护区 + tail 超预算 → `overBudget`（非发 doomed 请求）。
- [ ] UI context chip 与 runtime budget 计算一致。
- [ ] 新增 `CompactionWatermarkTests` + `TokenEstimatorTests`。

---

## 方案 4：Harness Task State（结构化结果 + 去重 + next-step nudge）（P2）

### 4.1 现状
- 工具结果是散文本（`ToolHandlerResult.handled(String)`）。
- `StuckGuard`/`LoopGuard`/`consecutiveReads` 是计数 + 散文 nudge，无结构化 kind、无 canonicalPath invalidate、无 reactive-only。

### 4.2 目标设计

```swift
// Tools/ToolEnvelope.swift (新增，统一工具结果)
public struct ToolEnvelope: Sendable {
    public let kind: ToolResultKind
    public let entries: [Entry]?       // listing 时携带
    public let content: String?        // file 时携带
    public let error: String?
    public let notFound: Bool
    public static func isError(_ text: String) -> Bool { ... }
}
public enum ToolResultKind: String, Sendable {
    case listing, file, notFound, error, other
}
public struct Entry: Sendable { public let path: String; public let kind: EntryKind }

// Loop/PatentTaskState.swift (新增)
public actor PatentTaskState {
    private var freshReads: [CanonicalCall: ToolEnvelope] = [:]
    private var listingWithoutReadCount = 0

    /// 分类结果 + 去重 + invalidate
    public func classify(_ envelope: ToolEnvelope, call: CanonicalCall) -> StateAction
    public func invalidate(path: String)          // 写操作后清 fresh read
    public func beginMessage()                    // 跨 message 重置 within-message 去重
}

public struct CanonicalCall: Hashable, Sendable {
    public let toolName: String
    public let canonicalArgs: String              // 规范化后的参数
}
public struct StateAction: Sendable {
    public let replay: ToolEnvelope?              // 非 nil 则重放，不执行
    public let nudge: String?                     // 非 nil 则注入 [System Notice]
}
```

规则：
- within-message：`(name, canonicalArgs)` 命中 fresh read → 重放原 envelope。
- 写操作 invalidate 该 path 的 fresh read（`read→edit→read验证` 不被短路）。
- reactive nudge：连续两次 listing 无中间 read 才触发；强模型首 listing 即 read 永不触发。
- nudge 是 `[System Notice]` system-attributed，transient（只骑一轮）。

`ToolHandlerResult` 的 `.handled(String)` 升级为 `.handled(ToolEnvelope)`，旧 String 入口做适配。

### 4.3 实施步骤
1. 新增 `ToolEnvelope` + `ToolResultKind`，`ToolDispatch` 的 handler 返回值升级（保留 String 适配）。
2. 新增 `PatentTaskState` + `CanonicalCall` + `canonicalPath` 规范化。
3. `PatentToolLoop`（方案 1）每轮：先 `classify`（可能重放/跳过执行）→ 执行 → `invalidate`（若写）→ nudge 注入。
4. 专利工具（检索/特征对比/权利要求解析）各自定义 kind（如检索结果 = `listing` of 命中条目，特征对比 = 结构化矩阵）。
5. 保留 `StuckGuard`/`LoopGuard` 作为兜底（编辑失败/迭代上限），与 `PatentTaskState` 并存。

### 4.4 风险与回退
- **风险**：canonicalArgs 规范化不当会误去重或漏去重。
- **回退**：canonicalPath 用 OSR 标准化（`..`/`.` 消除 + 绝对化），误判时显式 invalidate；reactive nudge 默认可关（policy 旋钮）。

### 4.5 验收检查清单
- [ ] `ToolEnvelope` 统一所有工具结果（kind/entries/content/error）。
- [ ] within-message 同 `(name, canonicalArgs)` 重放原 envelope（不重新执行）。
- [ ] 写操作后同 path 的 fresh read 被 invalidate。
- [ ] `read→edit→read验证` 不返回旧内容。
- [ ] reactive nudge 仅在"连续两次 listing 无中间 read"时触发；首 listing 即 read 不触发。
- [ ] nudge 为 `[System Notice]` 且 transient。
- [ ] 新增 `PatentTaskStateTests`（含 bias-disabled gate：note off 时模型仍能下降 read）。

---

## 方案 5：并行工具批处理 + 两阶段审批 + intra-batch dedupe（P2）

### 5.1 现状
- `ToolDispatch` 串行执行；已有 `readOnlyTools` 集合 + `dispatchWithHooks`（preToolUse/postToolUse）。
- `SubAgentEngine.spawnBatch` 是多 agent 并行，非单轮多工具并行。

### 5.2 目标设计

```swift
// Loop/ToolBatchExecutor.swift (新增)
public struct ToolBatchExecutor: Sendable {
    /// 两阶段：权限 gate 串行 resolve → 批准集 TaskGroup 并行
    public func execute(
        calls: [ToolCall],
        ctx: ToolContext,
        policy: PatentLoopPolicy,
        taskState: PatentTaskState,
        interceptor: (ToolEnvelope) -> LoopIntercept?
    ) async -> [ToolEnvelope]
}
```

规则：
1. **intercept 强制串行**：批内含 `complete`/`clarify`（`PatentToolLoop.interceptToolNames`）→ 回退串行，停首个 endRun。
2. **两阶段审批**：权限 gate 按 model order 串行 resolve（接 `HooksService`/`dispatchWithHooks`），拒绝则该 call + 后续全部 skip + 配对 rejection envelope。
3. **批准集并行**：TaskGroup 执行，结果按 model order 还原。
4. **intra-batch dedupe**：批内读类重复延迟到并行波后，按顺序对 live `PatentTaskState` 解析（兄弟成功则重放，失败则真执行）。
5. **state-before-cancel**：执行结果先入 `PatentTaskState` 再处理 cancel。

复用现有 `readOnlyTools` 判定读类（dedupe 候选）。

### 5.3 实施步骤
1. 新增 `ToolBatchExecutor`，单测覆盖：纯并行、含 intercept 串行、含拒绝串行、intra-batch dedupe。
2. `PatentToolLoop`（方案 1）的 `executeBatch` hooks 委托给 `ToolBatchExecutor`。
3. 接 `PatentTaskState`（方案 4）做 intra-batch dedupe。
4. 接 `LoopIntercept`（方案 2）做 intercept 串行。

### 5.4 风险与回退
- **风险**：并行执行下工具副作用顺序敏感（如两个写同 path）。
- **回退**：写类工具不参与 intra-batch dedupe（仅读类）；同 path 多写在批内串行（model order）。

### 5.5 验收检查清单
- [ ] 批内纯读 → TaskGroup 并行，结果按 model order 还原。
- [ ] 批内含 intercept → 串行，停首个 endRun。
- [ ] 权限拒绝 → 该 call + 后续 skip + 配对 rejection envelope，无 dangling tool_use。
- [ ] intra-batch 读类重复：兄弟成功重放、失败真执行。
- [ ] state-before-cancel：cancel 前结果已入 `PatentTaskState`。
- [ ] 新增 `ToolBatchExecutorTests`。

---

## 方案 6：Memory 成熟工程化（P1）

### 6.1 现状
- `MemoryEngine`（`MemoryEngine.swift`）同步 actor，`addSessionFact` 直接 append。
- `consolidate`/`consolidateDeep` 手动调用。
- 无延迟防抖、无 relevance gate、无后台 decay/merge/evict、无 FTS5/vector、无 token 预算。
- 存储：`MemoryStore` 文件 JSON（推测，未读但 `LLMMemoryStore.shared` 存在）。
- 领域模型 5 层（Working/Session/Case/LongTerm/Global）合理，保留。

### 6.2 目标设计

保留 5 层领域模型，重写工程化层：

```swift
// Memory/MemoryWritePath.swift (新增)
public actor MemoryWritePath {
    private var pendingSignals: [PendingSignal] = []
    private var debounceTask: Task<Void, Never>?

    /// 热路径：单次 SQL insert，无 LLM
    public func bufferTurn(user: String, assistant: String, caseId: String)

    /// 防抖 60s 或 session 切换 → flush → 单次 LLM 蒸馏整 session
    public func flush(caseId: String) async
}

// Memory/MemoryReadPath.swift (新增)
public actor MemoryReadPath {
    private var cache: [(CanonicalQuery, MemorySection)] = []  // 10s 缓存

    /// relevance gate → 选 ≤1 section → ≤800 token → prepend 到最新 user msg
    public func assemble(for query: String, caseId: String, budget: Int = 800) async -> MemoryBlock?
}
public enum MemorySection: Sendable { case identity, caseFacts, longTerm, transcript }

// Memory/MemoryConsolidator.swift (新增)
public actor MemoryConsolidator {
    /// 后台 24h：decay / merge / promote / evict / prune
    public func run() async
}
```

检索：FTS5 mirror 表（unicode61 折叠重音/大小写）作为 MVP，vector（bge-m3-mlx）后期接（复用 oMLX 占位）。
配置极简（对齐 osaurus 砍旋钮）：`enabled` / `extractionMode(sessionEnd/manual)` / `relevanceGateMode(off/heuristic/llm)` / `memoryBudgetTokens(800)` / `summaryDebounceSeconds(60)` / `consolidationIntervalHours(24)` / `salienceFloor(0.2)`。

### 6.3 实施步骤
1. `CaseContext`/`LongTermMemory` 加 `salience`/`sourceCount`/`useCount`/`lastUsed` 字段（方案 12 的 SQLite 迁移配合）。
2. 新增 `MemoryWritePath`：`bufferTurn` + 防抖 + `flush`（蒸馏 LLM 调用，每 session 一次）。
3. 新增 `MemoryReadPath`：relevance gate + 单 section + 10s 缓存。
4. 新增 `MemoryConsolidator`：decay/merge/evict/prune，后台 task。
5. `MemoryEngine` 改为协调三者，保留 5 层公共 API 向后兼容。
6. FTS5 mirror 表（方案 12 SQLite 迁移时建）。
7. `recoverOrphanedSignals`（启动时 drain pending）+ `syncNow`（UI 手动）。

### 6.4 风险与回退
- **风险**：蒸馏 LLM 调用失败 → 死循环重试。
- **回退**：bounded retries + dead-letter（osaurus 模式：terminal empty 立即 mark processed，缺模型保持 pending 等恢复）。

### 6.5 验收检查清单
- [ ] `bufferTurn` 仅 SQL insert，无同步 LLM。
- [ ] 蒸馏每 session 一次 LLM（非每轮）。
- [ ] 防抖 60s / session 切换 flush。
- [ ] relevance gate 选 ≤1 section，注入 ≤800 token。
- [ ] 10s 缓存避免重试重算。
- [ ] consolidator：decay `exp(-Δdays/30)`、merge Jaccard≥0.9、evict <0.2 且 idle 30 天。
- [ ] 蒸馏失败 bounded retry + dead-letter。
- [ ] `recoverOrphanedSignals` 启动 drain。
- [ ] 新增 `MemoryWritePathTests`/`MemoryReadPathTests`/`MemoryConsolidatorTests`。

---

## 方案 7：Frozen Manifest + capabilities_discover/load（P2）

### 7.1 现状
- `SkillManager.match`（`SkillManager.swift:12`）纯 `content.contains(trigger)` 关键词匹配。
- `ContextEngine.buildPrompt` 把 top3 skill **全量 body** 拼进 system prompt。
- `CapabilityRegistry` 已有 metadata（costLevel/idempotent），但仅注册表。

### 7.2 目标设计

```swift
// Skill/CapabilityManifest.swift (新增)
public struct CapabilityManifest: Sendable {
    public let entries: [ManifestEntry]   // session 冻结，KV-stable
    public let renderedBlock: String      // 注入静态 prefix 的目录块
}
public struct ManifestEntry: Sendable {
    public let name: String
    public let displayName: String
    public let description: String        // RAG 检索用
    public let kind: CapabilityKind        // .skill / .method / .tool
}

// Tools/CapabilityTools.swift (新增)
public enum CapabilityTools {
    public static let discover = ToolSpec(name: "capabilities_discover", ...)  // hybrid BM25+vector 检索目录
    public static let load = ToolSpec(name: "capabilities_load", ...)          // 加载具体 skill 指令
}

// Skill/CapabilityLoadBuffer.swift (新增)
public actor CapabilityLoadBuffer {
    /// mid-run load 的 pending specs，下一 user turn 才 drain 进 schema
    public func drain() -> [ToolSpec]
}
```

规则：
- session 开始冻结 manifest → 渲染进静态 prefix（byte-stable，配合方案 3）。
- skill 指令不全量注入；模型按需 `capabilities_discover`/`capabilities_load`。
- **deferred schema policy**：mid-run load 立即可调（registry dispatch by name），但 schema 快照冻结到下一 user turn（保 KV）。

检索 MVP：FTS5 over manifest descriptions（复用方案 6 的 FTS5）；vector（bge-m3）后期接。

### 7.3 实施步骤
1. 新增 `CapabilityManifest` + `ManifestEntry`，由 `CapabilityRegistry` + `SkillManager` 联合生成。
2. `ContextEngine` 用 manifest 目录块替换 top3 全量 body 注入。
3. 新增 `CapabilityTools.discover`/`load` + `CapabilityLoadBuffer`。
4. `ToolDispatch` 注册这两个工具，`load` 把 skill body 注入 transient context（不进静态 prefix）。
5. `SystemPromptComposer`（方案 1 后由 `PatentToolLoop` 承担）冻结 manifest，下一 user turn drain buffer。

### 7.4 风险与回退
- **风险**：RAG 检索不准导致 skill 不被发现。
- **回退**：manifest description 要求明确（RAG 用）；保留关键词 fallback；discover 可返回 top-K。

### 7.5 验收检查清单
- [ ] manifest session 冻结，渲染块 byte-stable（配合方案 3 断言）。
- [ ] skill 指令不全量进 prefix，按需 `capabilities_load`。
- [ ] mid-run load 立即可调，schema 下一 turn 才更新（KV 不破坏）。
- [ ] `capabilities_discover` 返回 top-K 匹配。
- [ ] 新增 `CapabilityManifestTests`/`CapabilityLoadBufferTests`。

---

## 方案 8：Privacy Filter（云端发送前 on-device 脱敏）（P0）

### 8.1 现状
- 无任何脱敏层。专利客户/发明人/技术秘密上云 = 泄密风险（合规红线）。
- 插入点：`ModelRouter.chat`（`ModelRouter.swift`）发送前。

### 8.2 目标设计

```swift
// Privacy/PrivacyFilter.swift (新增，放 YunPatCore 或独立 Privacy 包)
public actor PrivacyFilter {
    public func scrub(_ request: ScrubRequest) async -> ScrubResult
}
public struct ScrubRequest: Sendable {
    public let text: String
    public let provider: ModelProvider   // 本地 provider 不脱敏
    public let caseId: String            // 加载该案件的敏感词表
}
public struct ScrubResult: Sendable {
    public let scrubbedText: String
    public let detections: [Detection]
    public let blocked: Bool             // fail-closed：脱敏后复扫仍有泄漏 → true
    public let originalPreview: String   // review sheet 展示
}
public struct Detection: Sendable {
    public let entity: String
    public let kind: EntityKind           // .person/.email/.phone/.idNumber/.bankCard/.applicant/.custom
    public let placeholder: String        // [PERSON_1]
    public let source: DetectionSource    // .regex / .customList / .classifier
}

/// 客户级敏感词表（案件/客户/事务所三层）
public struct SensitiveTermsRegistry: Sendable {
    public func terms(for caseId: String) -> [String]
}
```

规则：
- 本地 provider（oMLX/Ollama）**不脱敏**。
- 云端 provider：确定性正则（邮箱/电话/证件号/银行卡/统一社会信用代码）+ 客户敏感词表（客户名/发明人/申请人）。
- **fail-closed**：脱敏后复扫，有泄漏 → `blocked = true`，阻止发送。
- 流式回复实时 unscrub 回填（占位符 → 原文）。
- review sheet 展示 scrubbed 预览，用户可批准/编辑。
- Insights 面板记录"云端实际看到的确切字节"。

### 8.3 实施步骤（MVP 先正则层）
1. 新增 `PrivacyFilter` + `Detection` + `SensitiveTermsRegistry`。
2. 正则层：邮箱、电话、身份证、银行卡、统一社会信用代码、URL、API key 形态。
3. 客户敏感词表：`.yunpat/sensitive/{case,client,firm}.txt`（对齐综合分析.md 建议 4 的 Rules 文件结构）。
4. `ModelRouter.chat` 前置 `PrivacyFilter.scrub`，`blocked` 则拒绝发送并提示。
5. 流式 chunk 回填 unscrub 映射。
6. UI：发送前 review sheet + Insights 审计面板。
7. （后期）on-device 分类器（`openai/privacy-filter` 或本地小模型）接 oMLX。

### 8.4 风险与回退
- **风险**：误脱敏（合法术语被替换）影响生成质量；unscrub 映射在长流式中错位。
- **回退**：占位符稳定（`[PERSON_1]` 全局唯一）；review sheet 允许用户手动排除；正则可配置开关。

### 8.5 验收检查清单
- [ ] 本地 provider 不脱敏。
- [ ] 云端 provider：邮箱/电话/证件号/银行卡/统一社会信用代码均被检测并替换。
- [ ] 客户敏感词表（case/client/firm 三层）生效。
- [ ] **fail-closed**：脱敏后复扫有泄漏 → 阻止发送。
- [ ] 流式回复占位符正确 unscrub 回填。
- [ ] review sheet 展示 scrubbed 预览。
- [ ] Insights 记录云端实际字节。
- [ ] 新增 `PrivacyFilterTests`（含 fail-closed 用例）。

---

## 方案 9：文件操作日志 + file_undo + shell mutation log（P1）

### 9.1 现状
- `FileSnapshotStore`（`Desktop/FileSnapshotStore.swift`）文件系统快照（粗暴回滚）。
- 综合分析.md 建议 2 已提 Git 语义化回滚（长期方案）。

### 9.2 目标设计（会话内精确撤销，零依赖过渡方案）

```swift
// Desktop/FileOperationLog.swift (新增)
public actor FileOperationLog {
    public func log(_ op: FileOperation)            // write/edit 记录
    public func history(path: String?) -> [FileOperation]
    public func undo(_ opId: UUID) async throws -> UndoResult
    public func undoLast(n: Int) async throws -> [UndoResult]
    public func undoAll(path: String) async throws -> [UndoResult]
}
public struct FileOperation: Sendable {
    public let opId: UUID
    public let kind: FileOpKind           // .write / .edit
    public let path: String
    public let beforeContent: String?     // edit 需恢复原文
    public let afterContent: String?
    public let timestamp: Date
    public let canUndo: Bool
    public let batchId: UUID?
}

// Desktop/ShellMutationLog.swift (新增)
public actor ShellMutationLog {
    /// 执行前规划 mv/cp/rm/mkdir，退出码 0 记录；不可解析标记 unloggable
    public func plan(command: String) -> [PlannedMutation]?
    public func commit(_ plan: [PlannedMutation]) 
}
```

工具注册：
- `file_undo` — 撤销最近 / 指定 op_id / 某 path 全部。
- `file_operation_history` — 查看本 session 操作历史。
- `write_file`/`edit_file` 执行成功后自动 `log`（dry_run 不 log）。

### 9.3 实施步骤
1. 新增 `FileOperationLog` + `FileOperation`（含 canUndo 判定）。
2. `write_file`/`edit_file` 工具 handler 接入 log。
3. 新增 `file_undo`/`file_operation_history` 工具。
4. 新增 `ShellMutationLog`：解析 `mv/cp/rm/mkdir`，执行前快照（rm 需原文），退出码 0 提交。
5. `FileSnapshotStore` 保留作为第二层保险（用户可选快照回滚或精确 undo）。

### 9.4 风险与回退
- **风险**：大文件 beforeContent 占内存；并发写同 path 日志顺序乱。
- **回退**：log 持久化到磁盘（`.yunpat/operations.log`）非纯内存；同 path 操作按时间戳排序。

### 9.5 验收检查清单
- [ ] `write_file`/`edit_file` 成功后记入 `FileOperationLog`，dry_run 不记。
- [ ] `file_undo` 可撤销最近 / 指定 op_id / 某 path 全部。
- [ ] `canUndo` 诚实标记（不可逆操作 false）。
- [ ] `ShellMutationLog`：`rm` 撤销需原文，`cp` 撤销删目标，`mv` 撤销移回。
- [ ] 不可解析命令（管道/glob/重定向）标记 unloggable + 结果警告。
- [ ] 同 batch 操作共享 batchId。
- [ ] 新增 `FileOperationLogTests`/`ShellMutationLogTests`。

---

## 方案 10：SessionSource 审计维度 + Agent DB（P3）

### 10.1 现状
- 无 session 来源标记。
- `CaseContext` 是 JSON 文本，非结构化案件 DB。

### 10.2 目标设计

```swift
// Models/Chat/SessionSource.swift (新增)
public enum SessionSource: String, Sendable, Codable {
    case chat, plugin, http, schedule, watcher, patentDraft, patentOA, patentSearch
}
public struct ChatSessionData: Sendable, Codable {
    public let id: UUID
    public let source: SessionSource
    public let sourcePluginId: String?
    public let externalSessionKey: String?
    public let dispatchTaskId: UUID?
}

// Storage/CaseDatabase.swift (新增，per-case 结构化 DB)
public actor CaseDatabase {
    /// 权利要求树 / 对比文件矩阵 / 审查意见逐条
    public func saveClaimsTree(_ tree: ClaimsTree, caseId: String) async throws
    public func saveComparisonMatrix(_ matrix: ComparisonMatrix, caseId: String) async throws
    public func saveOAPoints(_ points: [OAPoint], caseId: String) async throws
}
```

### 10.3 实施步骤
1. `ChatSessionData` 加 `SessionSource` + 来源字段。
2. Chat sidebar 显示来源 badge + 来源过滤栏。
3. dispatch task id == persisted session id（深链对齐）。
4. 新增 `CaseDatabase`（SQLite），权利要求树/对比矩阵/OA 逐条结构化存储。
5. `CaseContext` 升级：保留 JSON 兼容，新增结构化 DB 入口。

### 10.4 风险与回退
- **风险**：结构化 schema 变更频繁。
- **回退**：SQLite schema 版本化迁移（配合方案 12）。

### 10.5 验收检查清单
- [ ] 每个 session 带 `SessionSource` + 来源字段。
- [ ] sidebar 来源 badge + 过滤栏。
- [ ] dispatch task id == session id（深链）。
- [ ] `CaseDatabase` 结构化存储权利要求树/对比矩阵/OA。
- [ ] 新增 `CaseDatabaseTests`。

---

## 方案 11：分层架构强约束 + 命名约定文档化（P2）

### 11.1 现状
- 包结构已借鉴（YunPatCore/Networking/Desktop/Plugins/Sandbox）。
- 无强约束文档；`ContextEngine`/`CapabilityRegistry` 是 `@unchecked Sendable` final class（既非 Service actor 也非 Manager）。

### 11.2 目标设计

新增 `docs/ARCHITECTURE.md`，明文规则（对齐 osaurus CONTRIBUTING.md）：

| 层 | 规则 | 命名后缀 |
|---|---|---|
| Models | 纯数据，禁止 `@Published`/`static let shared` | — |
| Services | 业务逻辑，actor/stateless struct，禁止 `ObservableObject`/`@Observable` | `Service`/`Engine` |
| Managers | UI 状态，`@MainActor` + `@Observable` | `Manager` |
| Views | 按 feature 分文件夹，`Common/` 仅通用原语 | `View` |
| 持久化 | JSON 文件 → `Store`，SQLite → `Database` | `Store`/`Database` |

"代码该放哪"表 + 迁移指引。

### 11.3 实施步骤
1. 写 `docs/ARCHITECTURE.md`（规则 + 表 + 命名）。
2. 现有代码合规审计：`ContextEngine` → Service（actor 或 stateless struct）；`CapabilityRegistry` → Service。
3. 加 SwiftLint 规则（`.swiftlint.yml` 已存在）强制命名后缀。

### 11.4 风险与回退
- **风险**：合规审计改动面广。
- **回退**：分批迁移，优先新代码强制，旧代码渐进。

### 11.5 验收检查清单
- [ ] `docs/ARCHITECTURE.md` 存在，含规则 + 表 + 命名。
- [ ] `ContextEngine`/`CapabilityRegistry` 迁移到 Service 层。
- [ ] SwiftLint 规则强制 `Service`/`Engine`/`Manager`/`Store`/`Database`/`View` 后缀。
- [ ] 新增代码 100% 合规（CI gate）。

---

## 方案 12：Storage 收敛 + degraded 标记（P3）

### 12.1 现状
- 存储加密策略未明确（`MemoryStore` 文件 JSON）。

### 12.2 目标设计

```swift
// Storage/StorageConverger.swift (新增)
public struct StorageConverger {
    /// FileVault on → 明文 SQLite；off → opt-in SQLCipher
    public func converge(databases: [DatabaseConfig]) async
}

// Storage/DegradedStore.swift (新增)
public actor DegradedStore {
    /// Keychain key 丢失 → 标 degraded 不删库
    public func markDegraded(_ dbId: String, reason: DegradedReason)
    public func diagnostics(for dbId: String) -> DegradedDiagnostics  // 含 Retry/Reset
}
```

规则：默认明文 SQLite（依赖 FileVault）；可选 SQLCipher；Keychain 失效标 degraded（不删），Diagnostics 暴露原因 + Retry/Reset。

### 12.3 实施步骤
1. 评估当前 `MemoryStore` 是否迁移到 SQLite（配合方案 6 的 FTS5）。
2. 定义 `DatabaseConfig`（memory/case/methods/toolIndexes）。
3. 新增 `StorageConverger` + `DegradedStore`。
4. Settings → Storage 加密开关 + Diagnostics 面板。

### 12.4 风险与回退
- **风险**：JSON → SQLite 迁移数据丢失。
- **回退**：迁移脚本 + 旧 JSON 保留一个版本。

### 12.5 验收检查清单
- [ ] 明文 SQLite 默认，SQLCipher 可选。
- [ ] Keychain 失效标 degraded，不删库。
- [ ] Diagnostics 暴露原因 + Retry/Reset。
- [ ] FileVault 状态感知（on→明文倾向，off→加密倾向）。
- [ ] 新增 `StorageConvergerTests`/`DegradedStoreTests`。

---

# 第二部分：全局任务清单（按优先级 + 依赖排序）

## 依赖关系图

```
方案 11 (分层约束) ──────────────────────────────┐
方案 3 (KV-stable) ──┐                          │
方案 1 (单一驱动) ───┼──→ 方案 2 (Loop 工具) ────┤
方案 4 (TaskState) ──┤    方案 5 (批处理) ───────┤
方案 7 (manifest) ───┘                          ├──→ 方案 10 (Agent DB)
方案 6 (Memory) ────→ 方案 12 (Storage) ─────────┘
方案 8 (Privacy) ──── 独立
方案 9 (file_undo) ── 独立
```

## P0（必须，地基 + 合规）

| ID | 任务 | 依赖 | 预估 | 产出 |
|---|---|---|---|---|
| T-P0-1 | 方案 11：写 `docs/ARCHITECTURE.md` + 分层规则 | 无 | 0.5d | 文档 + SwiftLint 规则 |
| T-P0-2 | 方案 3：`TokenEstimator` + `ContextBudget` | 无 | 1d | 替换 `count/4` |
| T-P0-3 | 方案 3：`CompactionWatermark` | T-P0-2 | 2d | 替换 prefix 截断 |
| T-P0-4 | 方案 1：`PatentToolLoop` + `LoopExit`/`Policy`/`Hooks` 骨架 | T-P0-3 | 2d | 单一驱动（纯新增） |
| T-P0-5 | 方案 1：`AgentLoopEngine` 迁移为 Chat surface adapter | T-P0-4 | 1d | 委托 driver |
| T-P0-6 | 方案 1：`PatentLoopEngine` 迁移为 surface adapter（五步→阶段化 policy） | T-P0-5 | 2d | 删除嵌套 |
| T-P0-7 | 方案 1：`SubAgentEngine` 迁移为 driver 实例 | T-P0-6 | 1d | 三套→一套 |
| T-P0-8 | 方案 8：`PrivacyFilter` 正则层 + 客户敏感词表 | 无 | 2d | MVP 脱敏 |
| T-P0-9 | 方案 8：`ModelRouter` 前置脱敏 + fail-closed + unscrub | T-P0-8 | 1d | 发送前 gate |

## P1（架构增强，Loop 结构 + 撤销 + 记忆）

| ID | 任务 | 依赖 | 预估 | 产出 |
|---|---|---|---|---|
| T-P1-1 | 方案 2：`AgentLoopTools`（todo/complete/clarify）+ `validate(summary:)` | T-P0-7 | 1.5d | Loop 工具 |
| T-P1-2 | 方案 2：`LoopIntercept` + UI（checklist + overlay） | T-P1-1 | 1.5d | 拦截 + UI |
| T-P1-3 | 方案 9：`FileOperationLog` + `file_undo` | 无 | 1.5d | 会话内撤销 |
| T-P1-4 | 方案 9：`ShellMutationLog` | T-P1-3 | 1d | shell 撤销 |
| T-P1-5 | 方案 6：`MemoryWritePath`（bufferTurn + 防抖 + flush） | 无 | 2d | 异步写路径 |
| T-P1-6 | 方案 6：`MemoryReadPath`（relevance gate + 缓存） | T-P1-5 | 1.5d | 单 section 注入 |
| T-P1-7 | 方案 6：`MemoryConsolidator`（decay/merge/evict） | T-P1-5 | 1.5d | 后台维护 |

## P2（质量与成本优化）

| ID | 任务 | 依赖 | 预估 | 产出 |
|---|---|---|---|---|
| T-P2-1 | 方案 4：`ToolEnvelope` 统一结果 + `ToolResultKind` | 无 | 1d | 结构化结果 |
| T-P2-2 | 方案 4：`PatentTaskState`（去重 + invalidate + reactive nudge） | T-P2-1, T-P0-7 | 2d | Task State |
| T-P2-3 | 方案 5：`ToolBatchExecutor`（两阶段审批 + 并行 + dedupe） | T-P2-2, T-P1-2 | 2d | 批处理 |
| T-P2-4 | 方案 7：`CapabilityManifest` + frozen 渲染 | T-P0-3 | 1.5d | manifest 冻结 |
| T-P2-5 | 方案 7：`capabilities_discover`/`load` + `CapabilityLoadBuffer` | T-P2-4 | 1.5d | 按需加载 |
| T-P2-6 | 方案 11：现有代码合规审计（`ContextEngine`/`CapabilityRegistry` → Service） | T-P0-1 | 1d | 合规 |

## P3（长期演进）

| ID | 任务 | 依赖 | 预估 | 产出 |
|---|---|---|---|---|
| T-P3-1 | 方案 12：`StorageConverger` + `DegradedStore` | T-P1-5 | 2d | 存储策略 |
| T-P3-2 | 方案 12：JSON → SQLite 迁移（含 FTS5 mirror） | T-P3-1 | 2d | SQLite + FTS5 |
| T-P3-3 | 方案 10：`SessionSource` + sidebar 审计 | 无 | 1d | 来源标记 |
| T-P3-4 | 方案 10：`CaseDatabase`（权利要求树/对比矩阵/OA） | T-P3-2 | 2d | 结构化案件 |
| T-P3-5 | 方案 6/7：vector 检索（bge-m3-mlx 接 oMLX） | T-P3-2, T-P2-5 | 2d | 向量检索 |
| T-P3-6 | 方案 8：on-device 分类器（privacy-filter 模型） | T-P0-9, oMLX | 3d | 智能脱敏 |

**总预估**：P0 ≈ 12.5d / P1 ≈ 10.5d / P2 ≈ 9.5d / P3 ≈ 12d ≈ **44.5 人日**。

---

# 第三部分：总检查清单（验收 Gate）

## 架构完整性（方案 1/11）
- [ ] 单一 `PatentToolLoop` 驱动，Chat/Patent/SubAgent 三 surface 共用，仅 hooks/policy 不同。
- [ ] 无 `innerLoop.run` 嵌套。
- [ ] `LoopExit` 六态全覆盖。
- [ ] `docs/ARCHITECTURE.md` 存在，分层规则 + 命名约定明文。
- [ ] SwiftLint 强制命名后缀，新代码 100% 合规。

## Loop 结构（方案 2/4/5）
- [ ] `todo`/`complete`/`clarify` 三工具 + 拦截。
- [ ] `complete` summary 校验拒绝占位符（≥30 字实质）。
- [ ] `clarify` 暂停 + 用户答案恢复。
- [ ] 批内 intercept 强制串行。
- [ ] `ToolEnvelope` 统一结果（kind/entries/content/error）。
- [ ] within-message 去重 + 写 invalidate。
- [ ] reactive nudge 仅卡住时触发。
- [ ] 批处理：两阶段审批 + 并行 + intra-batch dedupe + state-before-cancel。

## 上下文工程（方案 3/7）
- [ ] `TokenEstimator` 中文友好（≥ count/2）。
- [ ] `CompactionWatermark` byte-stable（摘要逐字节重放、drop 不复活、note count-free）。
- [ ] 受保护区（首消息 + 最近 3 turn-pair）。
- [ ] overBudget 不发 doomed 请求。
- [ ] UI context chip 与 runtime 一致。
- [ ] manifest session 冻结，渲染块 byte-stable。
- [ ] skill 按需 `capabilities_load`，不全量注入。
- [ ] deferred schema policy（mid-run load 保 KV）。

## Memory（方案 6）
- [ ] 写路径延迟防抖（60s/session 切换 flush）。
- [ ] 蒸馏每 session 一次 LLM（非每轮）。
- [ ] 读路径 relevance gate + 单 section + ≤800 token + 10s 缓存。
- [ ] consolidator decay/merge/evict/prune。
- [ ] 蒸馏失败 bounded retry + dead-letter。
- [ ] `recoverOrphanedSignals` 启动 drain。

## 安全（方案 8/9）
- [ ] 本地 provider 不脱敏；云端正则 + 客户敏感词表。
- [ ] **fail-closed**：脱敏后复扫有泄漏阻止发送。
- [ ] 流式 unscrub 回填。
- [ ] review sheet + Insights 审计。
- [ ] `file_undo` 会话内精确撤销（最近/op_id/path 全部）。
- [ ] `canUndo` 诚实标记。
- [ ] `ShellMutationLog` unloggable 显式警告。

## 审计与存储（方案 10/12）
- [ ] `SessionSource` 来源标记 + sidebar badge/过滤。
- [ ] dispatch task id == session id。
- [ ] `CaseDatabase` 结构化（权利要求树/对比矩阵/OA）。
- [ ] 明文 SQLite 默认 + SQLCipher 可选。
- [ ] Keychain 失效标 degraded 不删库 + Diagnostics Retry/Reset。

## 测试与回归
- [ ] 所有新增模块有配套 `*Tests`（清单见各方案 5 节）。
- [ ] `PatentLoopEngineTests`/`AgentLoopEngineTests` 迁移后全绿。
- [ ] 新增 `PatentToolLoopTests`/`CompactionWatermarkTests`/`PrivacyFilterTests`/`PatentTaskStateTests`/`ToolBatchExecutorTests`/`MemoryWritePathTests`/`MemoryConsolidatorTests`/`FileOperationLogTests`。
- [ ] 中文 token 估算、KV byte-stable、fail-closed 三项有专项断言测试。

---

## 执行建议

1. **先合规后架构**：T-P0-8/9（Privacy Filter）与 T-P0-1（ARCHITECTURE.md）无依赖，可立即并行启动——前者是合规红线，后者是防腐护栏。
2. **地基三件套串行**：T-P0-2→T-P0-3→T-P0-4→T-P0-5→T-P0-6→T-P0-7 是单一驱动的主干，严格串行，每步独立可发布（旧 API 委托兼容）。
3. **Loop 工具在地基完成后**：T-P1-1/2 依赖 T-P0-7（三 surface 已统一）。
4. **独立项穿插**：T-P1-3/4（file_undo）、T-P1-5/6/7（Memory）与地基主干无依赖，可并行推进。
5. **每阶段设 Gate**：P0 完成后做一次回归（三 surface 统一 + 脱敏上线 + KV-stable），P1 完成后做第二次（Loop 结构 + 撤销 + 记忆工程化），再进入 P2/P3 优化。
