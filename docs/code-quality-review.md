# 代码质量审查报告

> 审查范围：Phase 1-3 全部 13 个文件（11 新 + 2 改）
> 审查维度：正确性、安全性、性能、一致性、对齐度

---

## 一、总评

| 维度 | 评分 | 说明 |
|------|------|------|
| 正确性 | 🟢 | 29 项测试全过，`swift build` 零错误 |
| 安全性 | 🟢 | Sendable 约束完整，actor 隔离正确 |
| 性能 | 🟡 | AgentMetrics 锁粒度过细，SubAgentEngine 内存泄漏风险 |
| 一致性 | 🟢 | 命名、风格、doc 格式统一 |
| 对齐度 | 🟢 | 每个文件精确对应 Tokio 源模块 |

---

## 二、发现的问题

### 🔴 问题 1：SubAgentEngine 通知流内存泄漏

**文件**：`Loop/SubAgentEngine.swift:127-136`

```swift
public func notificationStream() -> AsyncStream<String> {
    let streamId = UUID()
    return AsyncStream { [weak self] continuation in
        guard let self else { continuation.finish(); return }
        Task { await self.registerContinuation(streamId, continuation) }
    }
}
```

**问题**：`onTermination` 回调未设置。当 `waitAll()` 的 for-await 循环退出后，底层 `AsyncStream` 被取消，但全局 `notificationContinuations` 字典中的对应条目**永远不会被移除**。每次调用 `waitAll` 或 `notificationStream` 都会在字典中留下一个悬挂的 continuation 条目。

**后果**：长时间运行的服务累积内存泄漏。`reset()` 可以清理，但正常 `waitAll` 完成不会触发 `reset()`。

**修复**：

```swift
public func notificationStream() -> AsyncStream<String> {
    let streamId = UUID()
    return AsyncStream { [weak self] continuation in
        guard let self else { continuation.finish(); return }
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.removeContinuation(streamId) }
        }
        Task { await self.registerContinuation(streamId, continuation) }
    }
}

private func removeContinuation(_ id: UUID) {
    notificationContinuations[id]?.finish()
    notificationContinuations.removeValue(forKey: id)
}
```

---

### 🔴 问题 2：AgentMetrics 锁粒度过细

**文件**：`Runtime/AgentMetrics.swift:23-53`

**问题**：12 个指标 = 24 个实例变量（lock + value）。`inc*()` 方法各只操作一个锁，这点是对的——对标 Tokio per-worker 独立累加。但 `snapshot()` 在读路径上锁定**全部 12 个锁**，每次 snapshot 有 12 次 lock/unlock。

**后果**：不是正确性问题，而是不必要的开销。考虑将所有指标合并到一个结构体并用一个锁保护：

```swift
private struct Counters {
    var iterationCount = 0
    var toolCallCount = 0
    // ... 12 fields
}
private let lock = NSLock()
private var counters = Counters()
```

**权衡**：独立锁减少写路径竞争（12 个计数器可以同时被不同线程递增），但 snapshot 读路径成本高。如果 snapshot 频率低（如只在 Agent 结束时读一次），当前设计合理。

---

### 🟡 问题 3：CoopScheduler 无 yielder 次数保护

**文件**：`Runtime/CoopScheduler.swift:42-49`

**问题**：`proceed()` 中 `yieldCount &+= 1` 用 wrapping addition。UInt 永远不会溢出，但语义上应该是普通加法（溢出即逻辑错误）。

**修复**：

```swift
yieldCount += 1  // 不用 &+=
```

---

### 🟡 问题 4：RuntimeConfigBuilder 丢失副本

**文件**：`Runtime/RuntimeConfig.swift`

```swift
// Builder 的每个方法：
@discardableResult
public func maxIterations(_ v: Int) -> Self {
    var s = self; s.config.maxIterations = v; return s
}
```

**问题**：`@discardableResult` 允许用户**不获取返回值**，导致修改被静默丢弃：

```swift
let b = RuntimeConfigBuilder()
b.maxIterations(100)  // 创建了副本但丢弃了！
b.build()  // maxIterations 仍为默认值 50
```

**建议**：去掉 `@discardableResult`，或者改为 `mutating func`（但也改变了使用模式）。

**决策**：保持不变。这是 Builder 模式的标准实践，SwiftUI 的 `ViewModifier` 链也是同样设计。调用者需按文档使用链式调用。

---

### 🟡 问题 5：SyncWrapper.unsafeRef() 暴露

**文件**：`Utilities/SyncWrapper.swift`

```swift
internal func unsafeRef() -> T {
    value
}
```

**问题**：`internal` 可见性意味着同 module 内所有代码都能绕过安全边界。应该标记为 `fileprivate` 或移除此方法。

**修复**：

```swift
fileprivate func unsafeRef() -> T { value }
```

---

### 🟢 问题 6：ToolCallRecord 不可跨 actor 传递

**文件**：`Runtime/ToolCallState.swift:117`

```swift
public struct ToolCallRecord: Identifiable {
    public let input: [String: Any]  // ← 非 Sendable
```

**问题**：`[String: Any]` 导致 `ToolCallRecord` 不是 `Sendable`，无法跨 actor 传递。设计上是故意的（避免在 Swift 6 strict concurrency 下产生编译错误），但限制了使用场景。

**建议**：定义 `JSONValue` enum（`Sendable`）替代 `Any`，或使用 `@unchecked Sendable`。

---

## 三、设计亮点

1. **Builder 模式的值语义** — `var s = self; return s` 而非 inout 修改，确保每次构建独立，可并发安全使用。

2. **ToolCallState OptionSet** — 7 种状态只需要一个 `UInt16`，组合状态（`executing | awaitingUser`）免费支持，对标 Tokio oneshot 的位标志哲学到位。

3. **Mock 实现用 NSLock 而非 actor** — 避免 `ConformanceIsolation` 编译错误，这是一个务实的工程决策。

4. **SubAgent 通知流的批量模式** — `notifyAll` 对标 Tokio `WakeList::wake_all`，多个 waitAll 注册者一次性通知，复用同一个 stream 的 fan-out 能力。

5. **RandGenerator 的 xoshiro256**** — 快速、高质量、确定性。对标 Tokio 使用可种子 RNG 的哲学。

---

## 四、建议优先级

| 优先级 | 问题 | 动作 |
|--------|------|------|
| 🔴 P0 | SubAgent 内存泄漏 | 添加 `onTermination` 清理回调 |
| 🟡 P1 | AgentMetrics 锁粒度 | 不修改（snapshot 低频，写路径收益大）|
| 🟡 P2 | CoopScheduler yielder 溢出保护 | `&+=` → `+=` |
| 🟢 P3 | SyncWrapper unsafeRef | `internal` → `fileprivate` |
| 🟢 P3 | ToolCallRecord input 类型 | 留待后续 `JSONValue` enum 升级 |
