# Osaurus 优秀设计 → YunPat-Ai 引入分析

> 调研对象：`/Users/xujian/projects/参考架构/osaurus-main`（macOS AI Harness，纯 Swift，1465 文件 / 28716 符号）
> 分析日期：2026-06-28
> 范围：聚焦 Osaurus 独有、且本项目（专利代理人 AI 桌面应用）尚未吸收的成熟设计。
> 已剔除 `设计意见/` 下两份意见（claude.md、设计意见-开源案例综合分析.md）已覆盖的内容：Flow 模式、Git 语义化回滚、Plan Mode、Rules 文件系统、Capability Grouping、Architect/Editor 双模型、Hooks 双层检查、Diff 审查、Agent 线程、知识库双向同步、本地推理 fallback、UI 性能、色彩矛盾、平台版本分裂、插件崩溃隔离、记忆自动蒸馏、AXorcist 抽象。

---

## 本项目当前状态（差距基线）

| 模块 | 已有 | 缺口 |
|---|---|---|
| Loop | `PatentLoopEngine`（五步）内嵌 `AgentLoopEngine`；`SubAgentEngine` 三路并行 | 三套驱动，预算/去重/退出逻辑各写一遍；无 Loop 结构工具 |
| Context | `ContextEngine`（systemPrompt + skill top3 + user） | 超预算 `String.prefix` 截断破坏 prefix cache；token 估算 `char/4`（中文严重低估） |
| Memory | 5 层（Working/Session/Case/LongTerm/Global） | 同步 actor、手动 consolidate、无延迟防抖、无 relevance gate、无后台 decay/merge/evict、无 FTS5/vector |
| Skill | `SkillManager.match`（`content.contains` 关键词） | 无 RAG/BM25/vector；top3 全量 body 注入 system prompt |
| Capability | `CapabilityRegistry` + metadata（costLevel/idempotent） | 仅注册表，无 `capabilities_discover/load` 运行时发现、无 frozen manifest |
| Tool 执行 | `ToolDispatch` 串行 | 无并行批处理、无两阶段审批、无 intra-batch dedupe |
| 文件撤销 | `FileSnapshotStore`（文件系统快照） | 无会话内精确 undo log |
| 隐私 | 无 | 云端发送前无脱敏（专利客户信息上云=泄密） |
| 审计 | 无 | 无 SessionSource 来源标记 |
| 存储 | 未明确加密策略 | 无 degraded 降级标记 |

---

## 一、最高价值：架构层（决定上限）

### 1. 单一 Loop 驱动 + Policy 钩子（替代硬分叉/嵌套 Loop）⭐⭐⭐⭐⭐

**Osaurus 做法**：全应用只有**一个** `AgentToolLoop` 驱动。Chat、HTTP `/agents/{id}/run`、插件完成循环、`sandbox_reduce` 子代理、eval harness 都共用同一个迭代循环（预算记账、去重、next-step bias、批次排序、退出分类），只在分歧处用**命名的 Policy 旋钮**而非 fork：

| Knob | Chat | HTTP/Plugin |
|---|---|---|
| `maxIterations` | per-surface | per-surface |
| `stopOnToolRejection` | true | false |
| `dedupeNoticeEnabled` | true | false |

退出共 6 种：`finalResponse` / `iterationCapReached` / `toolRejected` / `cancelled` / `endedBySurface`(complete/clarify) / `overBudget`。

**本项目差距**：`PatentLoopEngine.run` 内部 `innerLoop.run`(AgentLoop) 是**嵌套调用**，`SubAgentEngine` 又是另一套。三套驱动，预算/去重/退出逻辑各写一遍，未来 Plugin/HTTP/Schedule 入口还要再写。

**落地建议**：抽出一个 `PatentToolLoop`（driver），`PatentLoopEngine` / `AgentLoopEngine` / `SubAgentEngine` 改为传入 `PatentLoopPolicy` 的 surface adapter。PatentLoop 的"五步"不再是 `run()` 内的硬编码步骤序列，而是 driver 的**阶段化 Policy**（事实抽取/规则检索/规划/执行/审查各自是一个 policy 阶段，guided flow 可提前 `endedBySurface`）。这是本项目架构能上到的最高台阶。

---

### 2. 三层 Loop 工具（todo / complete / clarify）+ 拦截机制 ⭐⭐⭐⭐⭐

**Osaurus 做法**：用三个最小 schema 的全局内置工具给 Loop **注入结构**，而不需要单独 planner：

- `todo(markdown)` — 写/替换任务清单（每次整表替换，UI 实时渲染 checklist）
- `complete(summary)` — 结束任务，**校验器拒绝占位符**（`done`/`ok`/`looks good` 一律 reject，要求 ≥30 字实质描述）→ 拦截后结束 Loop
- `clarify(question, options?, allowMultiple?)` — 暂停 Loop，底部 overlay 问一个关键问题，用户回答后从下一轮恢复

拦截在 `ToolRegistry.execute` 返回**之后**触发，且 `!ToolEnvelope.isError(resultText)` 才生效（被拒的 complete 落回模型重试）。拦截**跨 surface 对齐**：Chat 弹 banner、HTTP 返回 summary、插件发 COMPLETED/CLARIFICATION 事件。

**本项目差距**：`AgentLoopEngine.run` 是单次 chat 调用，没有 Loop 结构工具；`PatentLoopEngine` 的 guided flow 用 `return .needsClarification` 硬编码，不是工具驱动；没有 todo 的实时 checklist；complete 没有 summary 校验（模型可能糊弄"完成了"）。

**落地建议**：实现 `AgentLoopTools.swift`，注册 `todo`/`complete`/`clarify` 三个全局工具 + 一个 `LoopIntercept` 后处理器。`complete` 的 `validate(summary:)` 对专利场景尤其值钱——强制模型写"修改了权利要求 3 的引用关系，依据审查指南第二部分第三章 3.2.1"，而不是"已完成"。这直接对齐综合分析.md 建议 1（Flow 模式）的落地形态：**guided flow = complete/clarify 提前 endedBySurface**。

---

## 二、上下文工程层（直接决定云模型成本和质量）

### 3. KV-stable Context 压缩（byte-stable prefix）⭐⭐⭐⭐⭐

**Osaurus 做法**：`ContextBudgetManager` + `CompactionWatermark` 保证渲染出的 prompt prefix **跨迭代字节单调稳定**，这是 paged-KV prefix cache 复用的硬要求：

- 一旦某 tool result 被摘要，该摘要**永远逐字节重放**；一旦某消息被 drop，永远 drop
- 已发送过的 verbatim 消息老化时**只 drop 不重新摘要**（避免改写破坏 KV）
- trim note 是 **count-free** 的（`[Note: Earlier messages were trimmed…]`），多 drop 几条也不改其字节
- 窗口预留：system prompt + 工具集 + max_tokens，按 **effective budget = window × 0.85** 计算，UI context chip 和 runtime 永不矛盾

**本项目差距**：`ContextEngine.buildPrompt` 超预算时 `String(full.prefix(maxTokenBudget*4))`——**直接砍尾巴，破坏整个 prefix cache**，且 token 估算用 `char/4`（中文专利文书 char/4 严重低估）。

**落地建议**：引入 `CompactionWatermark`，替换 prefix 截断。中文 token 估算改用按 provider 的 tokenizer 或 `char/1.5`。这一项对云端 API 的延迟和成本影响极大（prefix cache 命中可降本 ~50%、降延迟 ~80%）。

---

### 4. Harness Task State（结构化结果 + 去重 + next-step nudge）⭐⭐⭐⭐

**Osaurus 做法**：把"工具结果是可操作对象而非散文"作为核心。`file_read` 目录返回 `kind:"listing"` + `entries[].path`（可直接复制），文件返回 `kind:"file"`，缺失返回 `not_found`。`AgentTaskState`：

- **去重**：同一 message 内 `(name, canonical args)` 命中过的 fresh read 直接重放原 envelope；写操作 invalidate 该路径的 fresh read（`read→edit→read验证` 不会被短路成旧内容）
- **reactive nudge**：连续两次 listing 没有中间 read（模型在乱逛）→ 注入 `[System Notice] 复制某个 entry.path`；nudge 只在模型卡住时才出现，强模型首 listing 即下降时**永不触发**（无 backseat-driving）

**本项目差距**：有 `StuckGuard`/`LoopGuard`/`consecutiveReads` 计数，但结果是散文字符串，没有结构化 kind 分类、没有 canonicalPath invalidate、没有 reactive-only 的 next-step bias。

**落地建议**：工具结果统一走 `ToolEnvelope { kind, entries?, content?, error? }`；`PatentTaskState` 对专利工具（检索结果/特征对比/权利要求解析）做结构化分类 + canonical 去重。这是小模型（DeepSeek/Qwen）当 planner 时"账记不住"的根本解法，直接提升复杂案件质量。

---

### 5. 并行工具批处理 + 两阶段审批 + intra-batch dedupe ⭐⭐⭐

**Osaurus 做法**：模型一轮发多个工具调用时，driver 批处理且**串行等价语义**：

- **两阶段审批**：权限 gate 按模型顺序串行 resolve（prompt 不堆叠/不竞态），拒绝则该批后续全部 skip + 配对 rejection envelope，批准集再 TaskGroup 并行执行，结果按模型顺序还原
- **intra-batch dedupe**：批内读类重复延迟到并行波之后、按顺序对 live state 解析
- **intercept 强制串行**：批内含 complete/clarify 则回退串行，停在首个 endRun

**本项目差距**：`ToolDispatch` 串行执行；专利三路并行分析（`runParallelAnalysis`）是 spawn 三个 SubAgent 而非单轮多工具批处理。

**落地建议**：`PatentToolLoop` 支持 single-step multi-tool-call 批处理。对专利场景，模型一轮同时调 `search_cnipa + search_google + search_local_db` 是常态，批处理 + 并发能显著降延迟。

---

## 三、Memory 层（本项目已有 5 层骨架，但缺成熟工程化）

### 6. Memory 成熟工程化模式 ⭐⭐⭐⭐

**Osaurus 做法**（三层：Identity / Pinned / Episodes + Transcript）：

- **写路径延迟 + 防抖**：每轮只做一次 SQL insert（`bufferTurn`），60s 防抖或 session 切换才 flush；蒸馏是**每 session 一次 LLM 调用**（覆盖 10+ 轮），绝不在请求路径同步调 LLM
- **读路径 gated + 单 section**：relevance gate（代词/"我们讨论过"/实体命中 → 选 section），最多注入 1 个 section，预算 ≤800 token，prepend 到最新 user message；10s 缓存避免重试重算
- **后台 consolidator**（24h）：decay（`salience *= exp(-Δdays/30)`）/ merge（Jaccard≥0.9 合并近重复 episode）/ promote / evict（<0.2 且 idle 30 天）/ prune
- **检索**：VecturaKit hybrid BM25+vector + MMR；不可用时 FTS5 mirror 表（unicode61 折叠重音/大小写）
- **配置极简**：v1 的 18 个旋钮砍到 10 个

**本项目差距**：`MemoryEngine` 是同步 actor，`addSessionFact` 直接 append，`consolidate`/`consolidateDeep` 是手动调用；没有延迟防抖写、没有 relevance gate、没有后台 consolidator 自动 decay/merge/evict、没有 FTS5/vector、没有 token 预算控制。5 层结构是对的，但**工程化（异步/防抖/decay/检索）几乎空白**。

**落地建议**：保留你的 5 层领域模型（Working/Session/Case/LongTerm/Global 对专利更有意义），但引入 osaurus 的工程化：蒸馏移出请求路径（session 结束防抖触发，一次 LLM 蒸馏整 session）、后台 consolidator 自动 decay 案件记忆、FTS5 mirror 表做法规/判例全文检索（比 contains 强太多）、读路径 relevance gate 控制注入 ≤800 token。

---

## 四、Skill / Capability 按需加载层

### 7. Frozen Manifest + capabilities_discover/load（RAG 按需加载，session 冻结保 KV）⭐⭐⭐⭐

**Osaurus 做法**：

- session 开始时把所有 enabled capability 写进 **enabled-capabilities manifest**，**冻结**进静态 prompt prefix（KV-stable）
- Skill 指令**不全量注入**，模型运行时用 `capabilities_discover`（hybrid BM25+vector 检索目录）+ `capabilities_load`（加载具体 skill 指令）按需拉取
- **deferred schema policy**：mid-run load 不立即重写 `<tools>` block（会破坏 prefix cache 字节），loaded 工具立即可调（registry dispatch by name），但 schema 快照冻结到下一 user turn 才更新

**本项目差距**：`SkillManager.match` 是纯 `content.contains(trigger)` 关键词匹配；`ContextEngine.buildPrompt` 把 top3 skill **全量 body 拼进 system prompt**——既不准（关键词）又费 token（全量注入），还破坏 prefix cache。

**落地建议**：实现 frozen manifest + `capabilities_discover`/`capabilities_load` 工具。专利 skill（权利要求撰写/OA答复/无效宣告/侵权分析）指令都很长，全量注入会吃掉大量 context；按需 RAG 加载 + frozen manifest 是质量和成本的双重优化。

---

## 五、安全 / 审计层（专利场景刚需，本项目缺失）

### 8. Privacy Filter（云端发送前 on-device 脱敏）⭐⭐⭐⭐⭐

**Osaurus 做法**：发往云端模型前，on-device 分类器（`openai/privacy-filter` 1.5B sparse-MoE，~2.8GB）+ 确定性正则（SSN/信用卡/IBAN/AWS key/GitHub token/自定义模式）检测 PII；每次检测在 review sheet 展示 scrubbed 预览；批准实体替换为稳定占位符（`[PERSON_1]`/`[EMAIL_2]`），流式回复实时 unscrub 回填；**fail-closed**：脱敏后再扫一遍，有泄漏则**阻止发送**；Insights 面板可查"云端实际看到的确切字节"。

**本项目差距**：无任何脱敏层。专利文书的**客户名称、发明人信息、技术秘密、商业细节**一旦上云就是泄密风险——这是专利代理人的**硬性合规红线**。

**落地建议**：这是专利 AI 区别于通用 AI 的**核心差异化安全能力**。建议引入确定性正则层（客户名/发明人/申请人/证件号/邮箱/电话/银行账号）作为 MVP，配合"客户敏感词表"（综合分析.md 建议 7 已提 Hooks，这里是发送前 gate，互补）。on-device 分类器可后期接入（已有 oMLX 占位）。

---

### 9. 文件操作日志 + file_undo + shell mutation log（会话内精确撤销）⭐⭐⭐

**Osaurus 做法**：每次 `file_write`/`file_edit` 记入 `FileOperationLog`，`file_undo` 可撤销最近/指定 op_id/某 path 全部 op；`shell_run` 的 `mv/cp/rm/mkdir` 在执行**前**规划、退出码 0 时记入 `ShellMutationLog`（rm 撤销需要执行前内容）；无法忠实解析的（管道/glob/重定向）标记 *unloggable* 并在结果里显式警告。

**本项目差距**：只有 `FileSnapshotStore`（文件系统快照）。综合分析.md 建议 2 已提出 Git 语义化回滚（长期方案），但 osaurus 的 file_undo 是**会话内、零依赖、即用**的过渡方案。

**落地建议**：作为 Git 回滚的**前置过渡**先落地 `FileOperationLog` + `file_undo`，零外部依赖、会话内即生效。法律文书的"撤销 AI 刚把'包括'改成'包含'"在 MVP 阶段就能实现。

---

### 10. SessionSource 审计维度 + Agent DB & Self-Scheduling ⭐⭐⭐

**Osaurus 做法**：

- 每个 session 带 `SessionSource` tag（chat/plugin/http/schedule/watcher）+ 源 plugin id + external key + dispatch task id，sidebar 显示来源 badge + 来源过滤栏
- Agent 可 opt-in 私有结构化 DB（自定义表/软删除/保存视图）+ 自调度（`schedule_next_run`/`cancel_next_run`/`notify`）

**本项目差距**：无来源审计；无 per-agent 持久化结构化存储（Memory 是键值/文本，不是结构化案件数据）。

**落地建议**：专利案件天然需要结构化存储（权利要求树/对比文件矩阵/审查意见逐条）。`CaseContext` 升级为 per-case 结构化 DB + SessionSource 标记（手动/检索/撰写/OA），对**可审计性**和**多入口追溯**价值高。

---

## 六、架构约束层（防止代码腐化）

### 11. 分层架构强约束 + 命名约定文档化 ⭐⭐⭐⭐

**Osaurus 做法**（CONTRIBUTING.md 明文规则）：

- **Models**：纯数据，**禁止** `@Published` / `static let shared`
- **Services**：业务逻辑，actor/stateless struct，**禁止** conform `ObservableObject`/`@Observable`，后缀 `Service`/`Engine`
- **Managers**：UI 状态，`@MainActor` + `@Observable`，后缀 `Manager`
- **Views**：按 feature 分文件夹，`Common/` 只放通用原语
- 持久化：JSON 文件 → `Store`，SQLite → `Database`

**本项目差距**：包结构已借鉴，但**无强约束文档**。`ContextEngine` 是 `@unchecked Sendable` final class（既非 Service actor 也非 Manager），`CapabilityRegistry` 同样；命名/职责边界容易随代码增长而模糊。

**落地建议**：在 `docs/` 下补一份 `ARCHITECTURE.md`，把分层规则 + 命名约定 + "代码该放哪"表固化。这是防止本项目专利领域逻辑（PatentLoop/FactBlackboard/LegalStateMachine/...）随迭代腐化的护栏。

---

## 七、存储层

### 12. Storage 收敛 + degraded 标记（plaintext default + opt-in SQLCipher）⭐⭐⭐

**Osaurus 做法**：0.21.0 起默认**明文 SQLite**（依赖 FileVault 静态保护），**可选** SQLCipher；**Keychain key 丢失时标 degraded 不删库**，Memory→Diagnostics 暴露真实原因 + Retry/Reset；之前的 always-on 加密被回退，因为缺 key 会静默 brick memory。

**本项目差距**：存储加密策略未明确。

**落地建议**：专利案件数据敏感，但**always-on 加密是反模式**（key 丢失 brick）。采用 osaurus 的 plaintext default + opt-in SQLCipher + degraded 标记三件套，Keychain 失效时降级而非数据丢失。

---

## 引入优先级矩阵

| 优先级 | 设计 | 对专利场景的价值 | 实施成本 | 说明 |
|---|---|---|---|---|
| **P0** | #8 Privacy Filter | 合规红线 | 低(正则)/高(模型) | 专利客户信息上云=泄密，MVP 先正则 |
| **P0** | #3 KV-stable 压缩 | 云模型成本/延迟 -50%/-80% | 中 | 当前 prefix 截断破坏 cache，中文 token 估算错误 |
| **P0** | #1 单一 Loop 驱动 | 架构上限 | 高 | 决定 Plugin/HTTP/Schedule 入口能否复用 |
| **P1** | #2 todo/complete/clarify | Loop 结构 + summary 校验 | 中 | complete 校验对法律文书糊弄零容忍 |
| **P1** | #9 file_undo | 会话内精确撤销 | 低 | Git 回滚的零依赖前置方案 |
| **P1** | #6 Memory 工程化 | 案件记忆不膨胀 | 中 | 5 层骨架已有，补异步/decay/FTS5 |
| **P2** | #4 Harness Task State | 小模型当 planner 的根本解 | 中 | 结构化结果+去重+nudge |
| **P2** | #7 frozen manifest+RAG | skill 长指令不全量注入 | 中 | 质量成本双优化 |
| **P2** | #5 并行工具批处理 | 多检索源并发降延迟 | 中 | 专利常需多源检索 |
| **P2** | #11 分层强约束 | 防专利逻辑腐化 | 低 | 补 ARCHITECTURE.md |
| **P3** | #12 Storage 收敛 | 加密不 brick | 低 | 策略决策 |
| **P3** | #10 SessionSource+AgentDB | 可审计/多入口追溯 | 中 | 案件结构化存储 |

---

## 总结

Osaurus 最值得引入的不是某个功能，而是 **#1 单一 Loop 驱动 + #2 三层 Loop 工具 + #3 KV-stable 压缩** 这三件套——它们一起构成了"让任意 LLM 在专利场景可靠跑多步任务"的工程地基，而本项目当前的 `PatentLoopEngine` 嵌套 `AgentLoopEngine` + prefix 截断 + 单次 chat 正是这块地基的缺口。Privacy Filter(#8) 则是专利场景区别于通用 AI 的合规护城河，建议 P0 先上正则层。

> 参考来源：Osaurus `docs/AGENT_LOOP.md`、`docs/MEMORY.md`、`docs/SKILLS.md`、`docs/CONTRIBUTING.md`、`docs/PRIVACY_FILTER.md`、`docs/STORAGE.md`
