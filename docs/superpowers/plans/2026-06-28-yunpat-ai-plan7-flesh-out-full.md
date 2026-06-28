# YunPat-Ai Plan 7: 补充血肉

> **定位**：本计划衔接已有 6 个 Plan + Osaurus Tools 计划，聚焦于**已有计划未覆盖或被跳过的关键体验与工程深度**。
> **前提**：Plan 1 骨架已完成约 85%，Plan 2-6 部分完成。本计划不重复已有任务，专注"骨骼已经在了，缺的是让产品可用的血肉"。
> **优先级**：P0（无此不可用）→ P1（专利核心能力）→ P2（桌面集成）→ P3（打磨）。

---

## 现状速览

| 已有 Plan | 行数 | 完成度 | 跳过/薄弱的环节 |
|---|---|---|---|
| Plan 1: Foundation | 2554 | 85% | **流式输出 UI 未流式化**、Token 预算注入未闭环 |
| Plan 2: Patent Intelligence | 2028 | 35% | **知识库检索管道空壳**、记忆蒸馏流程未实现、语义搜索未挂载 |
| Plan 3: Desktop Integration | 871 | 20% | AXorcist 空壳、文件回滚未实现、文档工作区未集成 |
| Plan 4: Ecosystem | 475 | 40% | 插件蓝图全部为空 |
| Plan 5: XiaoNuo Integration | 879 | 0% | 完全未动工 |
| Plan 6: Nuo Quality | 746 | 25% | Rubric 评分量表空壳、FactMarker 未集成 |
| Osaurus Tools | 1573 | 10% | per-tool AI 指导全部为空、CI 脚本空白 |

---

## P0：可用性底线（日常聊天+基础专利分析可用）

> 目标：用户打开 App 能正常聊天（流式输出），每次对话有上下文记忆，专利分析能检索到规则。

### Task P0-1: 流式聊天 UI —— 从"批处理"到"逐字输出"

**痛点**：当前 `modelStep` 回调收集全部 `fullResponse` 后返回，UI 在模型输出期间完全冻结。

**改动文件**：
- `Packages/YunPatCore/Sources/YunPatCore/Loop/PatentLoopHooks.swift` — 新增 `modelStream` 回调
- `Packages/YunPatCore/Sources/YunPatCore/Loop/PatentLoopHooks.swift` — `ModelStepResult` 新增 `.chunk(String)` 枚举
- `Packages/YunPatCore/Sources/YunPatCore/Loop/AgentLoopEngine.swift` — `makeHooks` 内改用 `modelStream` 逐块 yield
- `App/Views/ChatView.swift` — `ChatManager.sendMessage` 改为以 `AsyncStream<String>` 驱动 UI
- `App/Views/ChatView.swift` — `MessageBubble` 支持增量渲染（最后一条 assistant 消息）


#### Step 1: PatentLoopHooks 扩展流式回调

```swift
// PatentLoopHooks 新增字段
public typealias ModelStream = @Sendable ([Message], [ToolSpec]) async throws -> AsyncThrowingStream<ModelStepChunk, Error>

public let modelStream: ModelStream?  // 新增，优先于 modelStep

public enum ModelStepChunk: Sendable {
    case textDelta(String)    // 增量文本
    case toolCall(ToolCall)   // 完整工具调用
    case done(String)         // 完整响应文本 + 关闭流
    case error(String)
}
```

#### Step 2: AgentLoopEngine 适配流式输出

```swift
// AgentLoopEngine.makeHooks 中：
modelStream: { [modelRouter, provider, model] messages, _ in
    let chatReq = ChatRequest(model: model, messages: messages)
    let stream = try await modelRouter.chat(chatReq, provider: provider)
    return AsyncThrowingStream { continuation in
        Task {
            do {
                for try await chunk in stream {
                    switch chunk {
                    case .text(let t):
                        continuation.yield(.textDelta(t))
                    case .finish:
                        continuation.yield(.done(""))  // 文本已全部在 delta 中发送
                        continuation.finish()
                    case .error(let e):
                        continuation.yield(.error(e.localizedDescription))
                        continuation.finish()
                    default: break
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
},
```

#### Step 3: PatentToolLoop 支持流式 modelStream

```swift
// PatentToolLoop.run() 中：
if let modelStream = hooks.modelStream {
    let stream = try await modelStream(messages, tools)
    for try await chunk in stream {
        switch chunk {
        case .textDelta(let t):
            // 返回给 surface 渲染
            return await handleStreamingResponse(stream, initial: t, tools: tools, policy: policy, hooks: hooks)
        case .toolCall(let call):
            // 触发工具执行
            ...
        case .done(let text):
            return .finalResponse(text)
        case .error(let e):
            return .finalResponse("Error: \(e)")
        }
    }
} else {
    // 回退到旧 modelStep 模式
    let step = try await hooks.modelStep(messages, tools)
    ...
}
```

#### Step 4: ChatManager 流式驱动 UI

```swift
// ChatManager 新增
func sendMessageStreaming(in tabManager: TabManager) async {
    guard let activeID = tabManager.activeTabID,
          let idx = tabManager.tabs.firstIndex(where: { $0.id == activeID }),
          !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    let sentText = inputText
    inputText = ""
    isStreaming = true

    // 先插入空的 assistant bubble
    let placeholderId = UUID()
    tabManager.appendMessage(to: activeID, ChatMessage(id: placeholderId, role: .assistant, content: ""))

    // 流式运行
    let stream = await loopEngine.runStreaming(
        request: UserRequest(content: sentText),
        flow: tabManager.tabs[idx].loopPreference,
        model: tabManager.tabs[idx].loopModel
    )

    do {
        for try await delta in stream {
            tabManager.appendToLastMessage(to: activeID, delta)
        }
    } catch {
        tabManager.appendToLastMessage(to: activeID, "\n[Error: \(error.localizedDescription)]")
    }
    isStreaming = false
}
```

#### Step 5: TabManager 支持增量更新

```swift
// TabManager 新增
func appendToLastMessage(to tabId: UUID, _ delta: String) {
    guard let idx = tabs.firstIndex(where: { $0.id == tabId }),
          let lastIdx = tabs[idx].messages.indices.last else { return }
    tabs[idx].messages[lastIdx].content += delta
}
```

- [ ] **Step 1**: `PatentLoopHooks` 新增 `modelStream` 回调和 `ModelStepChunk` 枚举
- [ ] **Step 2**: `AgentLoopEngine.makeHooks` 提供 `modelStream` 实现
- [ ] **Step 3**: `PatentToolLoop.run` 优先使用 `modelStream`，回退 `modelStep`
- [ ] **Step 4**: `ChatManager` 新增 `sendMessageStreaming`，`TabManager` 新增 `appendToLastMessage`
- [ ] **Step 5**: 验证"发送一条消息 → 逐字出现在屏幕上"
- [ ] **Step 6**: Commit

---

### Task P0-2: 会话记忆 —— 让 Agent 记住当前对话

**痛点**：每次 `sendMessage` 都重新 `buildMessages()`，只包含系统提示词+当前用户消息，没有对话历史。

**改动文件**：
- `Packages/YunPatCore/Sources/YunPatCore/Memory/MemorySystem.swift` — 替换空壳为可用的 SessionMemory
- `Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryTypes.swift` — 确保 `SessionFact`、`SessionMemory` 类型完整
- `Packages/YunPatCore/Sources/YunPatCore/Loop/AgentLoopEngine.swift` — `makeHooks` 注入对话历史
- `App/Views/ChatView.swift` — `ChatManager.sendMessage` 传递历史消息


#### Step 1: SessionMemory 实现

```swift
// Memory/SessionMemory.swift
public struct SessionMemory: Sendable {
    public private(set) var messages: [Message] = []
    public private(set) var facts: [SessionFact] = []
    public let tabId: UUID

    public mutating func append(_ msg: Message) {
        messages.append(msg)
    }

    public mutating func recordFact(_ fact: SessionFact) {
        facts.append(fact)
    }

    /// 为下一次 LLM 调用构建消息历史
    public func buildHistory(systemPrompt: String, maxMessages: Int = 50) -> [Message] {
        let recent = Array(messages.suffix(maxMessages))
        return [Message(role: .system, content: systemPrompt)] + recent
    }
}
```

#### Step 2: Tab 模型绑定 SessionMemory

```swift
// Tab 新增字段
struct Tab: Identifiable {
    // ... 现有字段
    var sessionMemory: SessionMemory
}
```

#### Step 3: AgentLoopEngine 使用历史消息

```swift
// AgentLoopEngine.run() 接收历史消息
public func run(
    request: UserRequest,
    flow: AgentFlow,
    model: String? = nil,
    history: [Message] = []   // 新增参数
) async throws -> LoopResult {
    state = .running(step: "building-context")
    let systemPrompt = try await contextEngine.buildPrompt(for: request, flow: flow)
    let hooks = makeHooks(systemPrompt: systemPrompt, request: request, model: model ?? provider.defaultModel, history: history)
    // ...
}

private func makeHooks(systemPrompt: String, request: UserRequest, model: String, history: [Message]) -> PatentLoopHooks {
    PatentLoopHooks(
        buildMessages: {
            let base = [Message(role: .system, content: systemPrompt)]
            // 先放历史，再放当前请求
            var all = base + history
            all.append(Message(role: .user, content: request.content))
            return all
        },
        // ...
    )
}
```

#### Step 4: ChatManager 传递历史

```swift
// ChatManager.sendMessage 中：
let tab = tabManager.tabs[idx]
let history = tab.sessionMemory.messages
let result = try await loopEngine.run(
    request: UserRequest(content: sentText),
    flow: flow,
    model: model,
    history: history
)
// 完成后记录到 session memory
tabManager.tabs[idx].sessionMemory.append(Message(role: .user, content: sentText))
if case .completed(let text) = result {
    tabManager.tabs[idx].sessionMemory.append(Message(role: .assistant, content: text))
}
```

- [ ] **Step 1**: 实现 `SessionMemory` 完整类型
- [ ] **Step 2**: `Tab` 模型绑定 `SessionMemory`
- [ ] **Step 3**: `AgentLoopEngine` 接收 `history` 参数并注入 `buildMessages`
- [ ] **Step 4**: `ChatManager` 维护 `sessionMemory`，每次调用传入历史
- [ ] **Step 5**: 验证"先问技术领域 → 再问相关规则 → Agent 记得前面说的内容"
- [ ] **Step 6**: Commit

---

### Task P0-3: 知识库检索管道闭环 —— PatentLoop Step 2 真正工作

**痛点**：当前 `RuleEngine.retrieveRules(for:)` 是空实现，PatentLoop 五步中最重要的 Step 2 不产出任何规则。设计文档第12节有完整的六步检索管道，目前只落地了类型定义。

**改动文件**：
- `Packages/YunPatCore/Sources/YunPatCore/Knowledge/RuleEngine.swift` — 实现核心检索流程
- `Packages/YunPatCore/Sources/YunPatCore/Knowledge/WikiAdapter.swift` — 实现语义搜索挂载
- （不重复 Plan 2 已有的 `WikiTypes`、`FactExtractor` 等任务，Plan 2 Phase A-D 应同步推进）

**本 Task 聚焦 Plan 2 未覆盖的深度**：语义搜索实际挂载、跨源标注解析、冲突消解。

#### Step 1: WikiAdapter 语义搜索挂载

```swift
// WikiAdapter 新增方法
public func semanticSearch(_ query: String, topK: Int = 10) async throws -> [SemanticHit] {
    // 打开已有 .yunpat-semantic-index.sqlite (37.9MB, bge-m3)
    // 使用 SQLite vector 查询
    let indexPath = vaultPath.appendingPathComponent(".yunpat-semantic-index.sqlite")
    guard FileManager.default.fileExists(atPath: indexPath.path) else {
        return []  // 语义索引不可用时降级
    }

    // 1. 生成 query embedding (调用本地 bge-m3-mlx-8bit 或 API)
    let embedding = try await embeddingService.embed(query)

    // 2. 执行向量相似度搜索
    let hits = try await indexStore.semanticSearch(embedding: embedding, topK: topK)
    return hits
}
```

#### Step 2: RuleEngine 检索流程完善

```swift
// RuleEngine.retrieveRules 完整实现
public func retrieveRules(for facts: StructuredFacts) async throws -> ApplicableRules {
    // 1. 概念提取：从 facts.inventionPoints 提取法律概念
    let concepts = extractLegalConcepts(from: facts)

    // 2. 索引查询：查 Concept-Index.md → 获取 wiki 页面列表
    let wikiPages = try await wikiAdapter.lookupConcepts(concepts)

    // 3. 语义搜索兜底：未命中的概念走语义索引
    let missedConcepts = concepts.filter { c in !wikiPages.keys.contains(c) }
    if !missedConcepts.isEmpty {
        let semanticHits = try await wikiAdapter.semanticSearch(
            facts.problem + " " + facts.inventionPoints.joined(separator: " "),
            topK: 10
        )
        // 去重合并
        for hit in semanticHits {
            wikiPages[hit.concept] = hit.wikilinks
        }
    }

    // 4. 全文读取：读取命中的所有 wiki 页面 + 卡片
    let pages = try await wikiAdapter.readPages(Array(wikiPages.values.joined()))
    let cards = try await wikiAdapter.readCards(for: concepts)

    // 5. 跨源标注解析：检查 ⟷一致 / ⟷分歧 标记
    let crossRefs = try await wikiAdapter.readCrossReferences(concepts.joined(separator: " "))

    // 6. 组装 ApplicableRules
    return ApplicableRules(
        statutes: pages.filter { $0.module == .statute }.map(Statute.init),
        guidelines: pages.filter { $0.module == .guideline }.map(Guideline.init),
        precedents: pages.filter { $0.module == .precedent }.map(Precedent.init),
        conflicts: resolveConflicts(crossRefs),
        constraints: pages.filter { $0.module == .practice }.map(Constraint.init)
    )
}
```

- [ ] **Step 1**: `WikiAdapter` 语义搜索挂载（打开已有 SQLite，生成 embedding，topK 检索）
- [ ] **Step 2**: `RuleEngine.retrieveRules` 实现六步完整管道
- [ ] **Step 3**: `PatentLoopEngine.run` 中 Step 2 调用真实检索结果
- [ ] **Step 4**: 验证"输入技术方案 → Step 2 返回相关法条/审查指南章节/判例"
- [ ] **Step 5**: Commit

---

### Task P0-4: Token 预算感知 —— 防止上下文溢出

**痛点**：当前向 LLM 发送消息时不做 token 预算控制，对话历史长后就超出模型上下文窗口。

**改动文件**：
- `Packages/YunPatCore/Sources/YunPatCore/Context/CompactionWatermark.swift` — 完善压缩逻辑
- `Packages/YunPatCore/Sources/YunPatCore/Context/TokenEstimator.swift` — 中文优化
- `Packages/YunPatCore/Sources/YunPatCore/Loop/PatentToolLoop.swift` — 每次迭代前检查

#### Step 1: Tiered Compact 实现

```swift
// CompactionWatermark 完善
public struct CompactionWatermark {
    public func compact(
        messages: [Message],
        budget: ContextBudget,
        provider: ModelProvider
    ) -> CompactedResult {
        let estimated = TokenEstimator.estimate(messages: messages, provider: provider)
        let maxTokens = provider.defaultCapabilities.maxContextTokens

        if estimated > maxTokens * 0.9 {
            // Tier 1 (30K+): 旧轮次摘要为 1-2 句
            // Tier 2 (60K+): 更早期合并为段落
            // Tier 3 (100K+): 最早轮次丢弃，保留摘要
            return applyTieredCompact(messages: messages, maxTokens: maxTokens)
        }
        return CompactedResult(messages: messages, overBudget: false, note: nil)
    }
}
```

- [ ] **Step 1**: `TokenEstimator` 中文场景优化（当前 `count/2`，需改为按字符类型加权）
- [ ] **Step 2**: `CompactionWatermark` 实现 Tiered Compact（30K/60K/100K 三级）
- [ ] **Step 3**: `PatentToolLoop.run` 每次迭代前调用 `compactionWatermark.compact`
- [ ] **Step 4**: 验证"长对话自动压缩，不会溢出上下文窗口"
- [ ] **Step 5**: Commit

---

## P1：专利核心能力（Plan 2 深度补充）

> 目标：PatentLoop 五步真正可用，能完成一次完整的专利分析任务。

### Task P1-1: 评估引擎接入 Rubric 评分 —— Step 5 从占位到可审查

**痛点**：当前 `EvaluationEngine.evaluate` 是简单的 pass/fail 占位，不产出可操作的审查意见。

**联动 Plan 6**：`PatentRubric` 8 维评分量表已有类型定义，缺少的是集成和实现。

#### Step 1: PatentRubric 完整实现

```swift
// Quality/PatentRubric.swift
public struct PatentRubric {
    public let dimensions: [RubricDimension] = [
        .init(name: "法条引用准确性", weight: 0.20, checker: checkStatuteAccuracy),
        .init(name: "事实完整性", weight: 0.15, checker: checkFactCompleteness),
        .init(name: "规则一致性", weight: 0.15, checker: checkRuleConsistency),
        .init(name: "三步法逻辑", weight: 0.20, checker: checkThreeStepLogic),
        .init(name: "技术特征对比", weight: 0.10, checker: checkFeatureComparison),
        .init(name: "结论可靠性", weight: 0.10, checker: checkConclusionReliability),
        .init(name: "格式规范", weight: 0.05, checker: checkFormat),
        .init(name: "引用完备性", weight: 0.05, checker: checkCitations),
    ]

    public func evaluate(execution: ExecutionResult, rules: ApplicableRules, facts: StructuredFacts) -> RubricScore {
        var scores: [DimensionScore] = []
        for dim in dimensions {
            let result = dim.checker(execution, rules, facts)
            scores.append(DimensionScore(name: dim.name, score: result.score, weight: dim.weight, issues: result.issues))
        }
        let total = scores.reduce(0) { $0 + $1.weightedScore }
        return RubricScore(total: total, dimensions: scores, verdict: total >= 0.7 ? .pass : .fail)
    }
}
```

#### Step 2: EvaluationEngine 改用 Rubric

```swift
// PatentLoopEngine.run Step 5:
let rubricScore = evaluator.rubric.evaluate(execution: result, rules: rules, facts: facts)
if rubricScore.verdict == .pass {
    return .completed(artifacts.joined(separator: "\n\n"))
}
// 失败时返回详细维度和建议
let issues = rubricScore.dimensions
    .filter { $0.score < 0.6 }
    .map { Issue(description: "\($0.name): \($0.issues.joined(separator: "; "))") }
return .needsRevision(issues)
```

- [ ] **Step 1**: 实现 `PatentRubric` 8 维评分量表（Plan 6 Task 1 深度实现）
- [ ] **Step 2**: `EvaluationEngine` 改用 Rubric 评分替代简单 pass/fail
- [ ] **Step 3**: `PatentLoopEngine.run` Step 5 失败时返回具体维度的问题描述
- [ ] **Step 4**: 验证"提交一份分析结果 → 返回各维度得分 + 具体问题"
- [ ] **Step 5**: Commit

---

### Task P1-2: 技能系统语义匹配 —— RAG 自动选择 Skill

**痛点**：当前 `SkillManager.match()` 是纯关键词匹配（`.contains(trigger)`），设计文档要求的是"触发词精确匹配 + 语义匹配 (embedding cos-sim) + 标签匹配"三级 RAG。

#### Step 1: 语义匹配实现

```swift
// Skill/SkillManager.swift 新增
public func match(for request: UserRequest) async -> [SkillMatch] {
    var results: [SkillMatch] = []

    for skill in skills {
        var score: Double = 0

        // 1. 触发词精确匹配 → 权重 10
        for trigger in skill.manifest.triggers {
            if request.content.localizedCaseInsensitiveContains(trigger) {
                score += 10
                break
            }
        }

        // 2. 语义匹配 (embedding cos-sim) → 权重 0-5
        if let embeddingService = embeddingService {
            let similarity = await embeddingService.similarity(
                request.content,
                skill.manifest.description + " " + skill.manifest.tags.joined(separator: " ")
            )
            score += similarity * 5
        }

        // 3. 标签匹配 → 权重 2
        for tag in skill.manifest.tags {
            if request.content.localizedCaseInsensitiveContains(tag) {
                score += 2
            }
        }

        if score > 0 {
            results.append(SkillMatch(skill: skill, score: score))
        }
    }

    return results.sorted { $0.score > $1.score }
}
```

- [ ] **Step 1**: `SkillManager.match` 增加语义匹配层（需 `EmbeddingService`）
- [ ] **Step 2**: `ContextEngine.buildPrompt` 使用匹配到的 skill 内容注入
- [ ] **Step 3**: 验证"输入'撰写机械装置权利要求' → 自动匹配 claim-drafting skill"
- [ ] **Step 4**: Commit

---

### Task P1-3: 协作面板结构化确认 —— Step 2/4/5 注入点

**痛点**：五个协作注入点只有 Step 1 和 Step 3 有实现，Step 2（规则确认）、Step 4（中途干预）、Step 5（最终审核）空白。

**不重复 Plan 2 Phase D**（CollaborationPanel 基础 UI 已有模板），本 Task 聚焦：
1. Step 2 规则确认：检索到的法条/判例列表，用户可勾选/排除
2. Step 5 审查结果逐项确认：Rubric 评分后的 Issues 逐条处理
3. 中途暂停/恢复机制

#### Step 1: Step 2 规则确认注入

```swift
// PatentLoopEngine.run Step 2 之后：
if flow == .guided {
    let rulesList = rules.candidates.map { ApprovalOption(
        id: $0.wikilink,
        title: $0.rule.title,
        detail: $0.rule.summary
    )}
    state = .waitingApproval(ApprovalRequest(
        summary: "规则确认",
        detail: "以下规则是否适用于当前案件？",
        options: rulesList
    ))
    return .needsClarification(["请确认适用规则"])
}
```

#### Step 2: Step 4 中途干预

```swift
// PatentLoopEngine.run Step 4 内嵌循环中：
// 每完成一个 PlanStep 后，检查是否需要暂停
if flow == .guided && stepIndex % 2 == 0 {
    state = .waitingApproval(ApprovalRequest(
        summary: "执行进展 #\(stepIndex)",
        detail: "已完成 \(stepIndex) 个步骤，是否继续？",
        options: ["继续", "暂停审查"]
    ))
    return .needsClarification(["请确认是否继续"])
}
```

- [ ] **Step 1**: Step 2 规则确认注入（Guided 模式下展示检索结果让用户勾选）
- [ ] **Step 2**: Step 4 中途干预（每 N 步暂停确认）
- [ ] **Step 3**: Step 5 审查结果逐项确认（Rubric 维度得分展示 + 用户确认/驳回）
- [ ] **Step 4**: Commit

---

## P2：桌面集成（Plan 3 深度补充）

> 目标：Agent 能读写文件、执行 Shell 命令、操控桌面应用。

### Task P2-1: 文件操作工具集成到 Loop

**痛点**：`YunPatDesktop` 包有 `ShellExecutor` 和 `FileOperator`，但未注册到 `ToolDispatch`，LLM 无法调用。

- [ ] **Step 1**: 将 `ShellExecutor`、`FileOperator`、`VersionController` 的工具定义注册到 `CapabilityRegistry`
- [ ] **Step 2**: 在 `ToolDispatch` 中实现 `handleShell`、`handleFileRead`、`handleFileWrite` 等分发逻辑
- [ ] **Step 3**: `PatentToolLoop.registeredTools()` 包含桌面工具
- [ ] **Step 4**: 验证"让 Agent 读一个文件 → Agent 调用 file_read 工具 → 返回文件内容"
- [ ] **Step 5**: Commit

### Task P2-2: 文件回滚基础实现

- [ ] **Step 1**: `VersionController` 实现 Git 自动 commit（每次 Agent 写入后 `git add && git commit`）
- [ ] **Step 2**: 实现 `undoFile` / `file_operation_history` 工具
- [ ] **Step 3**: 验证"Agent 写文件 → 自动 commit → 用户可回滚到之前版本"
- [ ] **Step 4**: Commit

---

## P3：打磨与深度（设计文档 §11-15 剩余）

> 目标：文档工作区、UI 精致化、可观测性、插件生态。

### Task P3-1: 文档工作区基础 —— 分屏+标注解析

**不重复 Plan 3 Phase C**（已有 `DocumentWorkspace.swift` 和 `AnnotationParser.swift` 空壳），本 Task 聚焦让它们可用。

- [ ] **Step 1**: `AnnotationParser` 实现 `{del:}` `{ins:}` `{???}` 和 `💬` 标注语法解析
- [ ] **Step 2**: `DocumentWorkspace` 实现分屏布局（Chat + 文档编辑器左右分屏）
- [ ] **Step 3**: `DocumentChangeDetector` 通过 FSEvents 监听文档变更，计算 diff
- [ ] **Step 4**: 验证"在文档中写 `{del:旧文字}` 新文字 → Agent 感知变更"
- [ ] **Step 5**: Commit

### Task P3-2: 上下文压缩接入 Apple Intelligence

**痛点**：当前 `CompactionWatermark` 是朴素截断。设计文档要求使用 Apple FoundationModels 做本地摘要压缩（macOS 26+）。

- [ ] **Step 1**: 实现 `AppleIntelligenceSummarizer`（封装 `MLSummarizer`，macOS 26+）
- [ ] **Step 2**: 降级策略：macOS 15.5 使用 LLM API 调用做摘要
- [ ] **Step 3**: `CompactionWatermark.applyTieredCompact` 使用摘要器
- [ ] **Step 4**: Commit

### Task P3-3: 可观测性集成

**不重复 Plan 2 Phase F**（`TraceCollector` 和 `TraceStore` 基础已有），本 Task 聚焦集成到 Loop 中。

- [ ] **Step 1**: `PatentLoopEngine.run` 每个 Step 记录 `CapabilityTrace`
- [ ] **Step 2**: `AgentLoopEngine.run` 每次 LLM 调用记录 `PromptTrace`（hash 脱敏）
- [ ] **Step 3**: 请求结束后写入 `~/.yunpat/traces/{date}/{requestId}.json`
- [ ] **Step 4**: 验证"完成一次专利分析 → traces 目录生成完整链路 JSON"
- [ ] **Step 5**: Commit

### Task P3-4: UI 精致化 —— Liquid Glass + 沉浸感

**不重复 Plan 1 UI Tasks**（基础布局已有），本 Task 聚焦设计文档 §13 的"美且收敛"。

- [ ] **Step 1**: 侧栏使用 `.containerBackground(.thickMaterial)` 实现 Liquid Glass 材质
- [ ] **Step 2**: 协作面板使用 `.sheet` 样式，默认隐藏，有待确认自动弹出
- [ ] **Step 3**: 标签切换动画改为淡入淡出（`.transition(.opacity)`）
- [ ] **Step 4**: 工具栏只显示 SF Symbols 图标，文字标签 hover 显示
- [ ] **Step 5**: Commit

---

## 执行顺序建议

```
第 1 周  ████████  P0-1 流式UI (关键UX痛点)
         ████      P0-2 会话记忆 (基础可用性)

第 2 周  ██████    P0-3 知识库检索 (专利核心)
         ████      P0-4 Token预算 (稳定性)

第 3 周  ██████    P1-1 Rubric评分 (审查可用)
         ████      P1-2 语义匹配 (技能智能)

第 4 周  ████      P1-3 协作注入 (人机协作)
         ████      P2-1 文件工具 (桌面能力)

第 5 周  ████      P2-2 文件回滚 (安全)
         ████      P3-1 文档工作区 (专业体验)

第 6 周  ██        P3-2 上下文压缩 (深度优化)
         ██        P3-3 可观测性 (调试基础)
         ██        P3-4 UI精致化 (打磨)
```

## 与已有 Plan 的分工

| 本 Plan Task | 对应已有 Plan | 关系 |
|---|---|---|
| P0-1 流式UI | Plan 1 Phase E | Plan 1 实现了对话功能，本 Task 改流式化 |
| P0-2 会话记忆 | Plan 2 Phase E | Plan 2 有五层记忆概念，本 Task 先落地 Session 层 |
| P0-3 知识库检索 | Plan 2 Phase A-C | Plan 2 有类型和骨架，本 Task 实现检索管道 |
| P0-4 Token预算 | Plan 2 Phase E(压缩) | Plan 2 有概念，本 Task 实现 Tiered Compact |
| P1-1 Rubric评分 | Plan 6 Phase A | Plan 6 有类型定义，本 Task 实现评分逻辑+集成 |
| P1-2 语义匹配 | Plan 2 Phase C | Plan 2 有 SkillManager 骨架，本 Task 加语义层 |
| P1-3 协作注入 | Plan 2 Phase D | Plan 2 有 CollaborPanel UI，本 Task 实现业务注入 |
| P2-1 文件工具 | Plan 3 Phase B-C | Plan 3 有工具实现，本 Task 注册到 Loop |
| P2-2 文件回滚 | Plan 3 Phase D | Plan 3 有 VersionController，本 Task 集成 Git |
| P3-1 文档工作区 | Plan 3 Phase E | Plan 3 有空壳，本 Task 实现标注解析+分屏 |
| P3-2 上下文压缩 | Plan 2 Phase E | 补充 Apple Intelligence 摘要 |
| P3-3 可观测性 | Plan 2 Phase F | 补充集成到 Loop |
| P3-4 UI精致化 | Plan 1 Phase E | 补充设计文档 §13 的实现 |
