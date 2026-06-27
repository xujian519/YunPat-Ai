# 设计意见

------

## 🔴 需要修复的设计矛盾

**1. UI 色彩方案自相矛盾**

第 10 节与第 13 节直接冲突：

第 10 节指定了具体色值（`#1A1A2E`、`#E94560` 等），是典型的 Electron 风格自定义主题；第 13 节却明确说"不定义自己的主题色系统，深度跟随 macOS 系统色彩"，并将自定义颜色列为禁止模式。

建议：**删除第 10 节的硬编码色值**，全部替换为 `Color.primary`、`.secondary`、`.systemBackground` 等 AppKit 语义色。强调色跟 Accent Color，只有标注高亮（删除线/插入）保留半透明语义色。

**2. 平台版本分裂**

文档写 `macOS 15.5+`，但 Apple Containerization（沙箱 VM）是 macOS 26+ 才有的系统框架。两者差距极大，需要明确：

```
macOS 15.5+ → 完整功能 - 沙箱 VM
macOS 26+   → 全功能（含 Containerization + FoundationModels）
```

否则启动时沙箱 VM 入口按钮对 15.5 用户就是个无法使用的灰色按钮。

**3. 插件"崩溃隔离"描述不准确**

文档说"插件崩溃 → 底座不受影响"。但插件是运行时 dlopen 加载的 Swift Bundle，仍在同一进程内——Swift 的 `fatalError` 和越界崩溃会直接 kill 整个进程。

真正的崩溃隔离需要用 **XPC Service** 将每个插件运行在独立进程。要么升级为 XPC 方案，要么把描述改成"插件异常 → 标记插件故障，下次启动禁用"（进程级别的 catch，不是崩溃级别的隔离）。

------

## 🟡 架构层面的完善建议

**4. PatentLoop 模式判定过于脆弱**

当前判定逻辑是关键词匹配（含"专利检索/撰写/OA/无效/侵权"→ PatentLoop）。边界情况多：

- 用户在专利标签里问"帮我写个 Python 脚本提取 PDF 文字"——应走 AgentLoop
- "分析一下这段技术描述是否具备新颖性"——没有专利关键词，但应走 PatentLoop

建议在 TabType 上增加 `preferredLoop: LoopPreference` 枚举（`.auto` / `.forcePatent` / `.forceGeneral`），用户在标签设置中可覆盖；`.auto` 时走一次轻量 LLM 分类而非关键词匹配。

**5. 文档标注语法与普通 Markdown 冲突**

`~~删除~~` 在 GFM 是标准删除线，用户随手打个删除线就触发 Agent 感知；`<ins>` 是 HTML 标签，Obsidian/Typora 里可能直接渲染成下划线而不是标注语义。

建议两个方向选其一：

- 用专有前缀（如 `{del:原文}` / `{ins:新文}` / `{???}`），虽然不是标准 Markdown 但语义明确
- 或者用独立 annotation sidecar 文件（`.annotations.json`），不污染文档本身

**6. 多标签并发 API 配额控制缺失**

三个标签同时跑 AgentLoop，可能并发打出 3 × N 个 API 请求。文档没有提到全局并发预算或 API 速率限制处理。ModelBackend 协议里缺少：

```swift
protocol ModelBackend {
    var rateLimit: RateLimitInfo? { get }
    func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy
}
```

以及顶层的 `GlobalRequestQueue` 来跨标签协调并发量。

**7. 文档感知与 AgentLoop 执行的竞态未处理**

Step 4 执行阶段 AI 正在写入文档，用户同时也在文档工作区编辑——两个写入流冲突时如何处理？目前 `DocumentPerceptionMode.realtime` 会触发 `CollaborationEvent.documentChanged`，但 Loop 的 `LoopState` 枚举里没有"文档冲突等待"状态。

建议在 `LoopState` 增加：

```swift
case conflictPause(ConflictResolutionRequest)
```

Step 4 执行前先 lock 文档，用户编辑时弹确认框："AI 正在写入，是否暂停 AI 先让你编辑？"

**8. 知识库的 iCloud 路径是硬依赖**

`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/宝宸知识库` 这个路径假设了：iCloud Drive 已开启 + Obsidian 使用了这个存储位置。其他用户（包括未来的客户）不可能满足这个条件。

文档 12.7 里提到了"浏览..."按钮，说明你知道这个问题——建议把"首次启动自动扫描"改为"首次启动引导配置"，把 iCloud 路径只作为默认建议值，而不是自动关联的逻辑。

------

## 🟢 锦上添花的细节建议

**9. 记忆蒸馏应提供自动选项**

目前"用户手动决定是否蒸馏保存"是合理的隐私设计，但会导致重要上下文丢失。建议增加：

```
案件标签关闭时：
  ┌──────────────────────────────────────┐
  │ 是否保存本次会话记忆到案件上下文？     │
  │  [保存] [不保存] [总是自动保存]       │
  └──────────────────────────────────────┘
```

"总是自动保存"写入 UserPreferences，之后关标签直接蒸馏不弹框。

**10. 文档编号错误**

第 13 节（UI 设计哲学）的子节编号是 "12.1"、"12.2"……应该是 "13.1"、"13.2"。这会让文档内部引用混乱。

**11. AXorcist 依赖风险**

整个桌面自动化层建立在单一外部开源库上。建议在 `YunPatDesktop` 包内定义自己的 `DesktopAutomationProvider` 协议，AXorcist 作为协议的默认实现——这样即使 AXorcist 停止维护，替换成本只是实现一个新的 Provider，不影响上层代码。

**12. 构建顺序建议**

按依赖关系建议的交付顺序（避免后期返工）：

```
Phase 1: YunPatNetworking  → 多 API 后端均跑通（OpenAI/Claude/DeepSeek）
Phase 2: YunPatCore-基础   → AgentLoop + ToolRouter + 基础 Chat UI
Phase 3: 记忆系统          → 三层 SQLite + 蒸馏
Phase 4: 多标签 UI         → 标签管理 + 协作面板框架
Phase 5: PatentLoop        → 五步流程 + 知识库集成
Phase 6: 文档工作区        → 分屏 + 标注感知
Phase 7: YunPatDesktop     → AXorcist + Shell + 文件回滚
Phase 8: 插件框架          → 开放第三方
Phase 9: 沙箱 VM           → macOS 26+ only
```

Phase 1-4 完成后就有一个可演示的通用 AI 助手；Phase 5-6 完成后才是完整的专利版本。不要等 Phase 9 才发布——沙箱 VM 是加分项，不是核心功能。

------

总体来说，这份设计文档的深度非常罕见——PatentLoop 五步流程、双消费者知识库模式、三层记忆体系都是非常对路的设计。主要风险集中在色彩方案矛盾、平台版本分裂这两个需要尽早决策的问题上，以及插件隔离的描述需要与实际技术方案对齐。