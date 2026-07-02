# Tokio 设计模式引入实施计划

> 基础报告：`docs/tokio-architecture-analysis.md`
> 制定日期：2026-06-27
> 目标：将 Tokio 验证过的工程模式引入 YunPat-Ai (Swift 6)

---

## 总览：三个实施阶段

| 阶段 | 目标 | 工期 | 风险 |
|------|------|------|------|
| 🔴 Phase 1 | 配置系统 + 协作调度 + 指标 + 批量通知 | 3-4 工作日 | 低 |
| 🟡 Phase 2 | 模块重构 + 协议化 + 状态机 | 4-5 工作日 | 中 |
| 🟢 Phase 3 | 并发测试加固 + 长期优化 | 持续 | 低 |

---

## 🔴 Phase 1：MVP 前核心增强（预计 3-4 工作日）

### 背景

当前痛点：
- `LoopConfig` 只有 `maxRevisionCycles` 一个字段，散落配置（SubAgent 并发数硬编码 3、超时硬编码 120s）不可持久化
- `waitAll` 用 `Task.sleep(200ms)` 轮询，延迟高达 200ms
- Agent 连续执行工具调用会霸占 actor 线程
- 缺少指标系统，无法回答"这个任务花了多少 token"

---

### Task 1.1：创建 `RuntimeConfig` + `RuntimeConfigBuilder`

**目标文件**：新建 `Packages/YunPatCore/Sources/YunPatCore/Runtime/RuntimeConfig.swift`

**变更内容**：

```swift
// Runtime/RuntimeConfig.swift
import Foundation

// MARK: - Runtime Configuration

/// 对标 Tokio Builder + Config 分离模式
/// 所有运行时行为参数集中管理，支持 JSON 序列化
public struct RuntimeConfig: Sendable, Codable {

    // ── Agent 循环 ──
    /// 最大迭代次数
    public var maxIterations: Int = 50
    /// 每 N 次迭代检查中断/消息
    public var eventInterval: Int = 10
    /// 协作调度预算（每次工具调用消耗 1，耗尽后主动 yield）
    public var coopBudget: Int = 128

    // ── 子代理 ──
    /// 最大并发子代理数
    public var maxSubAgents: Int = 3
    /// 单个子代理超时（秒）
    public var subAgentTimeout: TimeInterval = 120
    /// 子代理失败重试次数
    public var subAgentRetry: Int = 1

    // ── 工具执行 ──
    /// 单个工具调用超时（秒）
    public var toolTimeout: TimeInterval = 30
    /// 工具调用失败最大重试次数
    public var maxToolRetries: Int = 2
    /// 连续只读次数阈值（超过则触发 nudge）
    public var readOnlyStreakLimit: Int = 10

    // ── Stuck Guard ──
    /// 编辑失败 nudge 阈值
    public var stuckNudgeThreshold: Int = 2
    /// 编辑失败放弃阈值
    public var stuckGiveUpThreshold: Int = 6

    // ── Context ──
    /// 压缩触发阈值（token 数）
    public var compactTokenThreshold: Int = 8000

    // ── 模型路由 ──
    /// 默认模型
    public var defaultModel: String = "deepseek-chat"
    /// 规划模型（复杂推理）
    public var planningModel: String = "claude-opus"
    /// 快速模型（分类 / 简单判断）
    public var fastModel: String = "deepseek-chat"

    // ── 调试 ──
    /// 是否启用详细日志
    public var verboseLogging: Bool = false

    public init() {}
}

// MARK: - Builder

/// RuntimeConfig 构建器 — 链式 API
public struct RuntimeConfigBuilder: Sendable {
    private var config = RuntimeConfig()

    public init() {}

    // Agent 循环
    public func maxIterations(_ v: Int) -> Self { var s = self; s.config.maxIterations = v; return s }
    public func eventInterval(_ v: Int) -> Self { var s = self; s.config.eventInterval = v; return s }
    public func coopBudget(_ v: Int) -> Self { var s = self; s.config.coopBudget = v; return s }

    // 子代理
    public func maxSubAgents(_ v: Int) -> Self { var s = self; s.config.maxSubAgents = v; return s }
    public func subAgentTimeout(_ v: TimeInterval) -> Self { var s = self; s.config.subAgentTimeout = v; return s }

    // 工具执行
    public func toolTimeout(_ v: TimeInterval) -> Self { var s = self; s.config.toolTimeout = v; return s }
    public func maxToolRetries(_ v: Int) -> Self { var s = self; s.config.maxToolRetries = v; return s }

    // 模型路由
    public func defaultModel(_ v: String) -> Self { var s = self; s.config.defaultModel = v; return s }
    public func planningModel(_ v: String) -> Self { var s = self; s.config.planningModel = v; return s }
    public func fastModel(_ v: String) -> Self { var s = self; s.config.fastModel = v; return s }

    // 调试
    public func verboseLogging(_ v: Bool) -> Self { var s = self; s.config.verboseLogging = v; return s }

    /// 构建最终配置
    public func build() -> RuntimeConfig { config }
}

// MARK: - Persistence

extension RuntimeConfig {
    /// 默认存储路径
    public static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".yunpat/config.json")
    }

    /// 加载配置，文件不存在则返回默认值
    public static func load(from path: URL = defaultPath) -> RuntimeConfig {
        guard let data = try? Data(contentsOf: path),
              let config = try? JSONDecoder().decode(RuntimeConfig.self, from: data)
        else { return RuntimeConfig() }
        return config
    }

    /// 持久化配置
    public func save(to path: URL = defaultPath) throws {
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: path, options: .atomic)
    }
}
```

**修改点**：
- `LoopConfig` → 废弃，改为 `RuntimeConfig`（通过 `maxIterations` 字段兼容）
- `SubAgentEngine` 中 `maxConcurrent = 3` → 从 `RuntimeConfig.maxSubAgents` 读取
- `waitAll` 的 `timeout = 120` → 从 `RuntimeConfig.subAgentTimeout` 读取
- `StuckGuard` 的 `nudgeThreshold = 2` → 从 `RuntimeConfig.stuckNudgeThreshold` 读取

**验收标准**：
```
# 1. JSON 序列化往返一致
RuntimeConfigBuilder().maxIterations(100).build() → let json = encode() → decode() → maxIterations == 100

# 2. 加载不存在的文件返回默认值
RuntimeConfig.load(from: nonexistent) → 所有字段为默认值

# 3. 保存后加载一致
config.save() → RuntimeConfig.load() → config == loaded
```

---

### Task 1.2：创建 `CoopScheduler`（协作调度器）

**目标文件**：新建 `Packages/YunPatCore/Sources/YunPatCore/Runtime/CoopScheduler.swift`

```swift
// Runtime/CoopScheduler.swift
import Foundation

// MARK: - Cooperative Scheduler

/// 对标 Tokio `task/coop` 的协作调度器
///
/// 每次工具调用 / LLM 推理前调用 `proceed()`，预算耗尽时主动 `Task.yield()`
/// 防止 Agent 循环长期霸占 actor 线程导致 UI 卡顿和其他标签饥饿。
///
/// 参考 Tokio 设计：
/// - `Budget(Option<u8>)` → `remaining: Int`, `unlimited: Bool`
/// - `poll_proceed()` → `proceed() async`
/// - `unconstrained()` → `unconstrained(_:) async`
public actor CoopScheduler {
    private let budgetLimit: Int
    private var remaining: Int
    private var inUnconstrained: Bool = false

    /// 已执行的 yield 次数（指标）
    public private(set) var yieldCount: Int = 0

    public init(budget: Int = 128) {
        self.budgetLimit = budget
        self.remaining = budget
    }

    /// 消耗 1 单位预算。耗尽时主动 yield 并重置。
    /// Agent 循环每次迭代开始时调用。
    public func proceed() async {
        guard !inUnconstrained else { return }
        remaining -= 1
        if remaining <= 0 {
            remaining = budgetLimit
            yieldCount += 1
            await Task.yield()
        }
    }

    /// 不消耗预算执行关键路径操作
    public func unconstrained<T: Sendable>(_ work: @Sendable () async -> T) async -> T {
        inUnconstrained = true
        defer { inUnconstrained = false }
        return await work()
    }

    /// 是否还有预算剩余
    public var hasBudgetRemaining: Bool {
        remaining > 0 || inUnconstrained
    }

    /// 重置为满预算
    public func reset() {
        remaining = budgetLimit
    }
}
```

**集成点**（修改 `PatentLoopEngine` 的 `run` 方法）：
```swift
// 在 loop 顶部注入：
private let coopScheduler: CoopScheduler

// 每次迭代前：
await coopScheduler.proceed()
```

**验收标准**：
```
# 1. 128 次调用后触发 yield
coop = CoopScheduler(budget: 5)
for _ in 0..<5 { await coop.proceed() }  // 不应 yield
await coop.proceed()  // 应触发 yield，yieldCount == 1

# 2. unconstrained 块不消耗预算
coop = CoopScheduler(budget: 5)
for _ in 0..<5 { await coop.proceed() }
await coop.unconstrained { await coop.proceed() }  // 不应 yield
// hasBudgetRemaining == false  ← 外部预算已耗尽

# 3. reset 回复满预算
coop = CoopScheduler(budget: 5)
for _ in 0..<5 { await coop.proceed() }
await coop.reset()
coop.hasBudgetRemaining == true
```

---

### Task 1.3：创建 `AgentMetrics`（无锁指标系统）

**目标文件**：新建 `Packages/YunPatCore/Sources/YunPatCore/Runtime/AgentMetrics.swift`

```swift
// Runtime/AgentMetrics.swift
import Foundation

// MARK: - Agent Metrics

/// 对标 Tokio `runtime/metrics/` 的无锁指标累加系统
///
/// 使用 `OSAllocatedUnfairLock` 保护每个指标，避免锁竞争。
/// 快照操作批量读取所有指标。
public final class AgentMetrics: @unchecked Sendable {
    private let _iterationCount = OSAllocatedUnfairLock(initialState: 0)
    private let _toolCallCount = OSAllocatedUnfairLock(initialState: 0)
    private let _toolErrorCount = OSAllocatedUnfairLock(initialState: 0)
    private let _toolRetryCount = OSAllocatedUnfairLock(initialState: 0)
    private let _llmInputTokens = OSAllocatedUnfairLock(initialState: 0)
    private let _llmOutputTokens = OSAllocatedUnfairLock(initialState: 0)
    private let _stuckNudgeCount = OSAllocatedUnfairLock(initialState: 0)
    private let _contextCompactCount = OSAllocatedUnfairLock(initialState: 0)
    private let _humanApprovalCount = OSAllocatedUnfairLock(initialState: 0)
    private let _yieldCount = OSAllocatedUnfairLock(initialState: 0)
    private let _subAgentCount = OSAllocatedUnfairLock(initialState: 0)
    private let _subAgentErrorCount = OSAllocatedUnfairLock(initialState: 0)
    private let _startTime = OSAllocatedUnfairLock(initialState: Date())
    private let _totalLatencyMs = OSAllocatedUnfairLock(initialState: 0.0)
    private let _latencySampleCount = OSAllocatedUnfairLock(initialState: 0)

    // MARK: - Increment

    public func incIteration() { _iterationCount.withLock { $0 += 1 } }
    public func incToolCall() { _toolCallCount.withLock { $0 += 1 } }
    public func incToolError() { _toolErrorCount.withLock { $0 += 1 } }
    public func incToolRetry() { _toolRetryCount.withLock { $0 += 1 } }
    public func addInputTokens(_ n: Int) { _llmInputTokens.withLock { $0 += n } }
    public func addOutputTokens(_ n: Int) { _llmOutputTokens.withLock { $0 += n } }
    public func incStuckNudge() { _stuckNudgeCount.withLock { $0 += 1 } }
    public func incContextCompact() { _contextCompactCount.withLock { $0 += 1 } }
    public func incHumanApproval() { _humanApprovalCount.withLock { $0 += 1 } }
    public func incYield() { _yieldCount.withLock { $0 += 1 } }
    public func incSubAgent() { _subAgentCount.withLock { $0 += 1 } }
    public func incSubAgentError() { _subAgentErrorCount.withLock { $0 += 1 } }

    /// 记录一次 LLM 推理耗时
    public func recordLatency(ms: Double) {
        _totalLatencyMs.withLock { $0 += ms }
        _latencySampleCount.withLock { $0 += 1 }
    }

    // MARK: - Snapshot

    /// 原子读取所有指标快照
    public func snapshot() -> AgentMetricsSnapshot {
        AgentMetricsSnapshot(
            elapsed: Date().timeIntervalSince(_startTime.withLock { $0 }),
            iterationCount: _iterationCount.withLock { $0 },
            toolCallCount: _toolCallCount.withLock { $0 },
            toolErrorCount: _toolErrorCount.withLock { $0 },
            toolRetryCount: _toolRetryCount.withLock { $0 },
            llmInputTokens: _llmInputTokens.withLock { $0 },
            llmOutputTokens: _llmOutputTokens.withLock { $0 },
            stuckNudgeCount: _stuckNudgeCount.withLock { $0 },
            contextCompactCount: _contextCompactCount.withLock { $0 },
            humanApprovalCount: _humanApprovalCount.withLock { $0 },
            yieldCount: _yieldCount.withLock { $0 },
            subAgentCount: _subAgentCount.withLock { $0 },
            subAgentErrorCount: _subAgentErrorCount.withLock { $0 },
            averageLatencyMs: _latencySampleCount.withLock { count in
                count > 0 ? _totalLatencyMs.withLock { $0 } / Double(count) : 0
            }
        )
    }
}

// MARK: - Snapshot

/// 指标快照 — 不可变，可直接发送给 UI
public struct AgentMetricsSnapshot: Sendable, Codable {
    public let elapsed: TimeInterval
    public let iterationCount: Int
    public let toolCallCount: Int
    public let toolErrorCount: Int
    public let toolRetryCount: Int
    public let llmInputTokens: Int
    public let llmOutputTokens: Int
    public let stuckNudgeCount: Int
    public let contextCompactCount: Int
    public let humanApprovalCount: Int
    public let yieldCount: Int
    public let subAgentCount: Int
    public let subAgentErrorCount: Int
    public let averageLatencyMs: Double
}
```

**集成点**：
- `PatentLoopEngine` 持有 `AgentMetrics` 实例
- 每次迭代 `metrics.incIteration()`
- 每次 LLM 调用 `metrics.addInputTokens(n)` / `metrics.addOutputTokens(n)` / `metrics.recordLatency(ms: t)`

**验收标准**：
```
# 1. 并发写入无数据竞争（TSan 通过）
for _ in 0..<1000 {
    Task { metrics.incToolCall() }
    Task { metrics.incToolError() }
}
await Task.sleep(.milliseconds(100))
snap = metrics.snapshot()
snap.toolCallCount + snap.toolErrorCount == 2000

# 2. 快照不可变且 JSON 可序列化
encode(metrics.snapshot()) → 成功
```

---

### Task 1.4：用 `AsyncStream` 批量通知替代轮询

**目标文件**：修改 `SubAgentEngine.swift`

**变更内容**：

```swift
// 在 SubAgentEngine 中添加：
private var notificationContinuations: [AsyncStream<String>.Continuation] = []

/// 注册通知流 — 替代 waitAll 的轮询
public func notificationStream() -> AsyncStream<String> {
    AsyncStream { continuation in
        notificationContinuations.append(continuation)
        // 当流被取消时自动清理
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeContinuation(continuation) }
        }
    }
}

private func removeContinuation(_ c: AsyncStream<String>.Continuation) {
    notificationContinuations.removeAll { $0 === c }
}

/// 子代理完成时批量通知所有注册者（对标 Tokio WakeList）
private func notifyAll(_ notification: String) {
    let batch = notificationContinuations
    for continuation in batch {
        continuation.yield(notification)
    }
}
```

**`waitAll` 改为基于通知的等待**：
```swift
public func waitAll(timeout: TimeInterval = 120) async -> [SubAgent] {
    guard activeCount > 0 else { return agents.filter { $0.status != .running } }

    let stream = notificationStream()
    let start = Date()

    for await notification in stream {
        if activeCount == 0 { break }
        if Date().timeIntervalSince(start) > timeout { break }
    }

    return agents.filter { $0.status != .running }
}
```

**验收标准**：
```
# 1. 子代理完成后 50ms 内通知到达（vs 当前 200ms 轮询）
sub = await engine.spawn(...)
let t0 = Date()
await engine.waitAll(timeout: 10)
let elapsed = Date().timeIntervalSince(t0)
elapsed < 0.05  // 50ms 内

# 2. 无子代理运行时 waitAll 立即返回
await engine.waitAll(timeout: 1)  // 不阻塞
```

---

### Task 1.5：将所有配置源统一到 `RuntimeConfig`，清理硬编码

**修改文件**：
1. `PatentLoopEngine.swift` — 接受 `RuntimeConfig` 替代 `LoopConfig`
2. `SubAgentEngine.swift` — `maxConcurrent` 从 `RuntimeConfig.maxSubAgents` 读取
3. `StuckGuard.swift` — 阈值从 `RuntimeConfig` 读取

**验收标准**：
```
# 全量编译通过
swift build  # 无错误

# 所有硬编码数字已替换
grep "= 3" Packages/YunPatCore/Sources/YunPatCore/Loop/SubAgentEngine.swift  # 最大值引用应来自 config
grep "= 120" ...  # 应来自 config.timeout
grep "= 200" ...  # millisecond 轮询应已替换为通知
```

---

### Phase 1 检查清单

- [ ] `RuntimeConfig` 和 `Builder` 编译通过
- [ ] `RuntimeConfig` JSON 往返序列化测试通过
- [ ] `CoopScheduler` 编译通过并集成到 `PatentLoopEngine`
- [ ] `CoopScheduler` 预算耗尽后 yield 测试通过
- [ ] `AgentMetrics` 编译通过并集成到 `PatentLoopEngine`
- [ ] `AgentMetrics` 并发写入无数据竞争（TSan）
- [ ] `SubAgentEngine` 通知流替代轮询编译通过
- [ ] `SubAgentEngine` 50ms 内通知到达测试通过
- [ ] 所有硬编码数字已替换为 `RuntimeConfig` 引用
- [ ] 全量 `swift build` 无错误
- [ ] 有指标的测试运行通过

---

## 🟡 Phase 2：架构增强（预计 4-5 工作日）

### Task 2.1：创建 `Utilities/` 模块（内部工具箱）

**目标**：对标 Tokio `util/`，提取可复用的内部工具

```
Packages/YunPatCore/Sources/YunPatCore/Utilities/
├── Bits.swift          # 对标 util/bit.rs — 位操作工具
├── WakeList.swift      # 对标 util/wake_list.rs — 批量通知
├── SyncWrapper.swift   # 对标 util/sync_wrapper.rs
└── RandGenerator.swift # 对标 util/rand.rs — 可种子 RNG
```

**Bits.swift**：
```swift
/// 对标 Tokio util/bit.rs，用于状态机位操作
public enum Bits {
    /// 打包两个 u32 到一个 u64（用于 token 计数等场景）
    @inlinable public static func pack(_ hi: UInt32, _ lo: UInt32) -> UInt64 {
        (UInt64(hi) << 32) | UInt64(lo)
    }
    @inlinable public static func unpack(_ v: UInt64) -> (UInt32, UInt32) {
        (UInt32(v >> 32), UInt32(v & 0xFFFF_FFFF))
    }
}
```

**验收标准**：
- 所有 `Utilities/` 文件编译通过
- `Bits` 打包/解包往返验证通过

---

### Task 2.2：协议化 `SubAgentEngine` 和 `ToolDispatch`（Runtime-agnostic）

**目标**：对标 Tokio 的"同步原语 runtime-agnostic"哲学，让核心组件可脱离具体实现测试

**协议提取**：

```swift
/// Runtime/AgentScheduler.swift

/// 对标 Tokio sync 的 runtime-agnostic 设计
/// 子代理调度器协议，允许实现替换（Actor / 单线程 / Mock）
public protocol AgentScheduler: Sendable {
    func spawn(name: String, prompt: String, projectFolder: String) async -> String
    func waitAll(timeout: TimeInterval) async -> [SubAgent]
    func cancelAll() async
}

/// 工具分派器协议
public protocol ToolDispatcher: Sendable {
    func dispatch(name: String, input: [String: Any], ctx: ToolContext) async -> ToolHandlerResult
    func register(name: String, handler: @escaping ToolHandler)
    var registeredTools: [String] { get async }
}

// Actor 实现（当前行为）
public actor ActorAgentScheduler: AgentScheduler {
    private let engine = SubAgentEngine.shared
    // 委托给 SubAgentEngine...
}

// Mock 实现（测试用）
public actor MockAgentScheduler: AgentScheduler {
    public private(set) var spawns: [(String, String)] = []
    public func spawn(name: String, prompt: String, projectFolder: String) async -> String {
        spawns.append((name, prompt))
        return "mock spawned"
    }
    // ...
}
```

**验收标准**：
- `PatentLoopEngine` 依赖 `AgentScheduler` 协议而非具体 actor
- 用 `MockAgentScheduler` 测试 `PatentLoopEngine.run()` 所有分支（不实际调用 LLM）

---

### Task 2.3：引入 `ToolCallState` 位标志状态机

**目标文件**：新增 `Packages/YunPatCore/Sources/YunPatCore/Runtime/ToolCallState.swift`

对标 Tokio `sync/oneshot.rs` 的 `State(usize)` 位标志模式：

```swift
/// 对标 Tokio oneshot State 的位标志状态机
public struct ToolCallState: OptionSet, Sendable, CustomStringConvertible {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let idle         = ToolCallState([])
    public static let queued       = ToolCallState(rawValue: 1 << 0)
    public static let executing    = ToolCallState(rawValue: 1 << 1)
    public static let awaitingUser = ToolCallState(rawValue: 1 << 2)
    public static let completed    = ToolCallState(rawValue: 1 << 3)
    public static let failed       = ToolCallState(rawValue: 1 << 4)
    public static let cancelled    = ToolCallState(rawValue: 1 << 5)
    public static let retrying     = ToolCallState(rawValue: 1 << 6)

    /// 终态集合
    public static let terminal: ToolCallState = [.completed, .failed, .cancelled]

    public var isTerminal: Bool { !isDisjoint(with: Self.terminal) }
    public var isActive: Bool { contains(.executing) }

    public var description: String {
        var parts: [String] = []
        if contains(.queued)       { parts.append("queued") }
        if contains(.executing)    { parts.append("executing") }
        if contains(.awaitingUser) { parts.append("awaitingUser") }
        if contains(.completed)    { parts.append("completed") }
        if contains(.failed)       { parts.append("failed") }
        if contains(.cancelled)    { parts.append("cancelled") }
        if contains(.retrying)     { parts.append("retrying") }
        return parts.isEmpty ? "idle" : parts.joined(separator: "|")
    }
}
```

**验收标准**：
- `.executing | .awaitingUser` 同时成立（位标志核心优势）
- `.terminal` 包含 `.completed`, `.failed`, `.cancelled`
- `isTerminal` 对所有终态返回 true
- 选项不多于 16 个（UInt16 上限，设计约束）

---

### Task 2.4：YunPatCore 模块化拆分

**目标**：按职责拆分子模块，同步更新 `Package.swift`

当前 YunPatCore `Sources/YunPatCore/` 结构：
```
Loop/ Context/ Hooks/ Skill/ Patent/ Knowledge/ Quality/ Trace/
Memory/ Desktop/ Capability/ SystemPrompt/
```

提议拆分后：
```
Loop/          → 保持，精简为 Loop + StuckGuard + 状态
Context/       → 保持
Hooks/         → 保持
Runtime/       → 新增：RuntimeConfig, CoopScheduler, AgentMetrics, ToolCallState
Utilities/     → 新增：Bits, WakeList, SyncWrapper, RandGenerator
Skill/         → 保持
Patent/        → 保持
Knowledge/     → 保持
Quality/       → 保持
Trace/         → 保持
Memory/        → 保持
Capability/    → 保持
SystemPrompt/  → 保持
Desktop/       → 移到 YunPatDesktop package
```

**验收标准**：
- `swift build` 全部通过
- 各模块的 import 关系是 DAG（无循环依赖）
- `Desktop/` 移动后不破坏 YunPatCore 编译

---

### Phase 2 检查清单

- [ ] `Utilities/Bits.swift` 编译通过，位操作测试通过
- [ ] `Utilities/WakeList.swift` 编译通过
- [ ] `AgentScheduler` 协议定义，`ActorAgentScheduler` 实现
- [ ] `ToolDispatcher` 协议定义
- [ ] `MockAgentScheduler` 编译通过，可测试 PatentLoop
- [ ] `ToolCallState` 编译通过，终态判断正确
- [ ] YunPatCore 模块拆分完成，`swift build` 通过
- [ ] 无循环依赖检查通过
- [ ] 全量测试通过
- [ ] VulcanView 中集成 CoopScheduler (并发场景)

---

## 🟢 Phase 3：长期优化（持续性工作）

### Task 3.1：并发测试加固

| 测试目标 | 方法 | 工具 |
|---------|------|------|
| SubAgent 并发调度 | 100 子代理并发 spawn，验证无遗漏/无死锁 | Swift Testing + TaskGroup |
| ToolDispatch 并发注册 | 多 actor 同时 register/unregister | TSan (Thread Sanitizer) |
| AgentMetrics 并发写入 | 1000 个 Task 同时增计数器 | TSan |
| ContextEngine 并发压缩 | 监听器并发触发压缩 | TSan |

**验收标准**：所有并发测试在 TSan 下零告警通过。

---

### Task 3.2：编译时条件门控（对标 Tokio Feature Flags 思路）

Swift 中可使用 `#if canImport()` + Xcode Build Settings 实现类似效果：

```swift
#if canImport(YunPatPlugins)
    public let pluginEnabled = true
#else
    public let pluginEnabled = false
#endif
```

或者创建 Xcode 项目配置预设：
- `Debug` — 全部启用
- `Release` — 全部启用
- `Minimal` — 仅 Core + Networking（用于 CI 快速编译）

**验收标准**：Minimal 配置下编译速度 < Debug 的 50%。

---

## 附录：关键对应关系

| Tokio 源 | YunPat 目标 | 状态 |
|----------|------------|------|
| `runtime/config.rs` | `Runtime/RuntimeConfig.swift` | Phase 1 Task 1.1 |
| `runtime/builder.rs` | `RuntimeConfigBuilder` | Phase 1 Task 1.1 |
| `task/coop/mod.rs` | `Runtime/CoopScheduler.swift` | Phase 1 Task 1.2 |
| `runtime/metrics/` | `Runtime/AgentMetrics.swift` | Phase 1 Task 1.3 |
| `util/wake_list.rs` | `SubAgentEngine` 通知流 | Phase 1 Task 1.4 |
| `sync/mod.rs` (agnostic) | `AgentScheduler` 协议 | Phase 2 Task 2.2 |
| `sync/oneshot.rs` (State) | `ToolCallState` 位标志 | Phase 2 Task 2.3 |
| `util/bit.rs` | `Utilities/Bits.swift` | Phase 2 Task 2.1 |
| `util/sync_wrapper.rs` | `Utilities/SyncWrapper.swift` | Phase 2 Task 2.1 |
| `util/wake.rs` | `Utilities/WakeList.swift` | Phase 2 Task 2.1 |
| `loom/` | TSan + 参数化测试 | Phase 3 Task 3.1 |
| `macros/cfg.rs` | Build Settings 预设 | Phase 3 Task 3.2 |

---

## 风险与缓解

| 风险 | 概率 | 缓解 |
|------|------|------|
| `OSAllocatedUnfairLock` 在旧 macOS 不可用 | 低 | fallback 到 `NSLock` |
| `AsyncStream.Continuation` 引用循环 | 中 | `onTermination` + `weak self` |
| 协议化增加编译时间 | 低 | 限制协议方法数量 ≤ 5 |
| 模块拆分破坏 import 路径 | 中 | 每步 `swift build` 验证 |
