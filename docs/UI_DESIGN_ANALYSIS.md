# YunPat-Ai 桌面端 UI 设计调查分析报告

> 调查日期: 2026-07-05
> 调查范围: `App/` 目录下全部 SwiftUI 视图文件 (35 个 .swift 文件)
> 技术栈: Swift 6 + SwiftUI + AppKit, macOS 15.5+, Apple Silicon only

---

## 一、整体架构概览

### 1.1 布局架构: Zed Editor 风格的三 Dock 系统

YunPat-Ai 桌面端采用**借鉴 Zed Editor 的三 Dock 容器化布局**，通过 `HSplitView` 实现左/中/右三栏，底部叠加全宽 Dock 和状态栏，形成五区结构:

| 区域 | 容器 | 可见性控制 | 默认状态 |
|------|------|-----------|---------|
| Left Dock | HSplitView 左栏 | `leftDockVisible` | 显示 (caseList 面板) |
| Center | HSplitView 中栏 | `centerMode` 枚举 | `.chat` |
| Right Dock | HSplitView 右栏 | `rightDockVisible` | 隐藏 |
| Bottom Dock | VStack 底部全宽 | `bottomDockVisible` | 隐藏 |
| StatusBar | VStack 最底部 | `centerMode != .focusWriting` | 始终显示 |

**核心设计原则** (来自 `docs/UI_DESIGN.md`):
1. Dock 容器化 — 左/右/底三 Dock 各容纳多面板
2. 单 Bool 控显隐 — 每个 Dock 可见性 = 一个 `@Published` 属性
3. StatusBar 为唯一入口 — 面板切换按钮集中在底部状态栏
4. Panel 协议抽象 — 统一面板行为规范
5. 中心区 CenterMode 枚举 — 无嵌套 if-else
6. 递归而非正交 — 消灭散落 @State，归并为 3 Dock + 1 CenterMode

### 1.2 状态管理: AppStateStore 单一数据源

```
AppStateStore (Combine 响应式)
├── Dock 系统
│   ├── leftDockVisible: Bool = true
│   ├── rightDockVisible: Bool = false
│   ├── bottomDockVisible: Bool = false
│   └── centerMode: CenterMode = .chat
├── 面板选择
│   ├── leftDockActivePanel: LeftDockPanel = .caseList
│   └── rightDockActivePanel: RightDockPanel = .collaboration
├── 专注写作快照
│   └── focusWritingRestoreState: FocusWritingSnapshot?
├── 撤销/重做
│   └── undoManager: UndoManager
└── 废弃旧状态 (6 个 @available(*, deprecated) 变量)
```

**特点**: 正在从旧状态体系迁移到新 Dock 状态体系，存在 6 个已废弃但保留的旧变量，迁移完成度约 60%。

---

## 二、设计系统分析 (DesignTokens)

### 2.1 间距系统: 8pt 网格

| Token | 值 | 用途 |
|-------|-----|------|
| `Spacing.unit` | 8pt | 网格基准 |
| `Spacing.xxs` | 4pt | 极小间距 (图标内) |
| `Spacing.xs` | 8pt | 小间距 |
| `Spacing.sm` | 16pt | 标准间距 |
| `Spacing.md` | 24pt | 中等间距 |
| `Spacing.lg` | 32pt | 大间距 |
| `Spacing.xl` | 40pt | 超大间距 (空状态) |
| `Spacing.xxl` | 48pt | 最大间距 |

### 2.2 圆角系统

| Token | 值 | 用途 |
|-------|-----|------|
| `CornerRadius.xs` | 4pt | 小标签 |
| `CornerRadius.sm` | 6pt | 状态栏按钮 |
| `CornerRadius.md` | 8pt | 标签行、输入区 |
| `CornerRadius.lg` | 12pt | 消息气泡 |
| `CornerRadius.xl` | 16pt | 输入栏、Clarify 覆盖层 |
| `CornerRadius.xxl` | 20pt | 大卡片 |
| `CornerRadius.full` | 9999 | 圆形 (发送按钮) |

### 2.3 字体系统: HIG 语义字体

采用 Apple Human Interface Guidelines 语义字体，支持 Dynamic Type:
- `FontStyle.largeTitle` → `Font.largeTitle`
- `FontStyle.title` → `Font.title`
- `FontStyle.headline` → `Font.headline` (面板标题)
- `FontStyle.body` → `Font.body` (正文/消息)
- `FontStyle.bodyMonospaced` → `Font.body.monospaced()` (文档编辑器)
- `FontStyle.callout` → `Font.callout` (Tab 标题/列表行)
- `FontStyle.caption` → `Font.caption` (辅助文本)
- `FontStyle.caption2` → `Font.caption2` (时间戳/元数据)

### 2.4 图标尺寸

| Token | 值 | 用途 |
|-------|-----|------|
| `IconSize.toolbar` | 16pt | 工具栏图标 |
| `IconSize.sidebar` | 14pt | 侧边栏图标 |
| `IconSize.inlineSmall` | 12pt | 行内小图标 |
| `IconSize.caption` | 11pt | Tab 图标 |
| `IconSize.emptyState` | 40pt | 空状态图标 |
| `IconSize.avatar` | 28pt | 头像 |
| `IconSize.messageIcon` | 24pt | 消息内图标 |

### 2.5 颜色系统: 双层语义

**第一层: 系统 NSColor 映射** (`Color+App.swift`)
- Surface: `appBackground`, `appSurfacePrimary/Secondary/Tertiary/Quaternary`
- Text: `appTextPrimary/Secondary/Tertiary/Placeholder`
- Separator: `appSeparator`, `appGridLine`
- Control: `appControlBackground/Highlight/Text`

**第二层: 业务语义色** (`DesignTokens.swift`)
- Status: `statusWarning` (orange), `statusSuccess` (green), `statusRunning` (blue), `statusDestructive` (red)
- Annotation: `annotationDeletion` (red), `annotationInsertion` (green), `annotationQuestion` (orange), `annotationComment` (blue)
- Bubble: `appBubbleUser` (accent 12% opacity), `appBubbleAssistant` (controlBackground)
- Soft badges: `appStatusSuccessSoft` (green 12%), `appStatusWarningSoft` (orange 12%)

### 2.6 阴影系统

| Token | opacity | radius | offset | 用途 |
|-------|---------|--------|--------|------|
| `AppShadow.sm` | 0.04 | 2 | 0,1 | 轻微浮起 |
| `AppShadow.md` | 0.06 | 6 | 0,3 | 卡片 |
| `AppShadow.lg` | 0.08 | 12 | 0,6 | 弹出层 |
| `AppShadow.glow` | 0.25 | 8 | 0,0 | 焦点发光 |

### 2.7 动画系统

| Token | 时长 | 用途 |
|-------|------|------|
| `AnimationDuration.fast` | 0.15s | 按钮 hover |
| `AnimationDuration.normal` | 0.2s | 面板切换 |
| `AnimationDuration.slow` | 0.25s | Dock 显隐 |
| `AnimationDuration.spring` | 0.35s | 专注写作切换 |
| `AnimationDuration.bouncy` | 0.45s | 弹性效果 |

---

## 三、核心 UI 组件分析

### 3.1 ContentView — 主窗口骨架

```
VStack(spacing: 0) {
    HSplitView {
        leftDockSection     // 左 Dock (条件渲染)
        mainSection         // 中心区 (始终渲染)
        rightDockSection    // 右 Dock (条件渲染)
    }
    if bottomDockVisible: DocumentWorkspace  // 底部 Dock
    if !focusWriting: StatusBar               // 状态栏
}
```

**关键设计**:
- 使用 `HSplitView` 实现可拖拽调整的三栏布局
- Dock 区域通过 `if` 条件渲染实现显隐，配合 `.animation()` 过渡
- 专注写作模式隐藏所有装饰性 UI，仅保留 `DocumentWorkspace`
- `ContentViewModifiers` 封装了菜单事件、工具栏、文件导入等逻辑

### 3.2 Tab 系统 — 多会话管理

**TabManager** 管理两类标签:
- `general` — 通用对话标签 (默认 autoFlow)
- `patent` — 案件专用标签 (默认 fullAgent)

**ChatTab 数据模型**:
- 基础: `id`, `title`, `type`, `messages[]`
- Agent 状态: `loopState`, `loopPreference`, `autoFlowEnabled`, `loopModel`
- 会话记忆: `sessionMemory`
- 案件关联: `caseId`, `workspacePath`
- Agent 交互: `todoChecklist`, `clarifyRequest`

**TabBar 视觉**:
- 活跃 Tab: `accentColor.opacity(0.15)` 背景 + `fontWeight(.semibold)`
- 运行中: `circle.circle` 脉冲动画 + `statusRunning` 蓝色
- 关闭按钮: `xmark` + `caption2` 字号

### 3.3 StatusBar — 三段式状态栏

```
[Left: 面板切换]  |  [Center: 操作]  |  [Right: Dock toggle + 状态]
[案][工作区][知]  |  [附件][保存][同步]  |  [浏览器][协作][文档]  已连接
```

- 高度: 固定 34pt (`PanelWidth.statusBarHeight`)
- 背景: `.thickMaterial` 毛玻璃
- 按钮: `HitTarget.small` (28pt) + hover 状态动画
- 活跃态: `accentColor` 前景 + `accentColor.opacity(0.12)` 背景

### 3.4 消息系统 (ChatView / MessageBubble)

**MessageBubble 视觉规范**:
- 用户消息: 右对齐 + `appBubbleUser` 背景 (accent 12%) + accent 描边 (18% opacity)
- 助手消息: 左对齐 + `appBubbleAssistant` 背景 + separator 描边 (40% opacity)
- 圆角: `CornerRadius.lg` (12pt)
- 头像: 28pt 圆形, 用户 `person.fill`, 助手 `sparkles`
- 流式输入: 三点脉冲动画 (0.45s, 递减透明度)
- 时间戳: `caption2` + `.tertiary` (仅非流式消息显示)
- 上下文菜单: 复制 (`Cmd+C`)

**InputBar 视觉规范**:
- 圆角胶囊: `CornerRadius.xl` (16pt)
- 焦点态: `accentColor.opacity(0.5)` 描边
- 发送按钮: 28pt 圆形, accent 色, 禁用态 `appSurfaceTertiary`
- 快捷键: `Cmd + Enter` 发送

### 3.5 侧边栏 (CaseListSidebar)

- 背景: `.thickMaterial` 毛玻璃
- 筛选器: segmented Picker (全部/案件/通用/归档)
- 列表样式: `.sidebar`
- 行布局: 图标 + 标题 + 案件号 + Flow 徽章
- 上下文菜单: 归档 / 关闭
- 底部统计: 会话数 + 归档数

### 3.6 文档工作区 (DocumentWorkspace)

- 编辑器: `TextEditor` + `bodyMonospaced` 字体
- 标注系统: 四种类型 (删除/插入/疑问/备注), 各有专属颜色
- 同步模式: 手动同步 / 实时同步 (segmented Picker)
- 标注条: 水平滚动, 40pt 高, 按类型着色
- 空状态: 提示拖拽或点击附件按钮

### 3.7 协作面板 (CollaborationPanel)

- 待确认事项列表 (从 `loopState.waitingApproval` 提取)
- 空状态: `checkmark.circle` 大图标
- 卡片式展示: checkpoint + 标题 + 详情

### 3.8 案件关系图 (CaseGraphView)

- 本案卡片: 蓝色高亮 + `doc.text.magnifyingglass` 图标
- 关系类型: 优先权(orange) / 分案(purple) / 引用(gray) / 族(green) / 接续(teal)
- 关系行: 图标 + 类型 + 标题 + 申请号
- 空状态: 引导在案件标签中查看

### 3.9 专利浏览器 (PatentBrowser)

- 内嵌 WKWebView (AppKit 桥接)
- 五个预设: Google Patents / CNIPA / Espacenet / WIPO / USPTO
- 导航栏: 后退/前进/网址/刷新/PDF下载
- PDF 下载: 正则提取专利号 → GooglePatentsClient

### 3.10 Clarify 覆盖层

- 底部固定, `regularMaterial` 背景 + `CornerRadius.xl`
- 单选/多选/自由输入三种模式
- 选项按钮: `accentColor.opacity(0.1)` 背景
- 快捷操作: 跳过 / 确认

### 3.11 设置页面

五标签设置面板 (520x480pt):
1. **接口** (ProviderSettingsView) — API Key 管理, 云端/本地分类
2. **技能** (SkillSettingsView)
3. **插件** (PluginSettingsView)
4. **MCP** (MCPSettingsView)
5. **知识库** (KnowledgeSettingsView)

### 3.12 模型选择器 (ModelPickerPopover)

支持 11 个模型供应商, 280pt 宽 Popover:
- DeepSeek / OpenAI / Anthropic / GLM / Qwen
- OpenRouter / SiliconFlow / Mistral / Together
- MLX (本地) / Ollama (本地)
- 自定义模型输入 + API Key 配置入口

---

## 四、交互模式分析

### 4.1 三种 Agent Flow 模式

| 模式 | 枚举 | 图标 | 用途 |
|------|------|------|------|
| 自由问答 | `.copilot` | `circle` | 直接对话无需确认 |
| 分步撰写 | `.guided` | `circle.dotted` | 逐步确认, 适合专利稿 |
| 自动代理 | `.fullAgent` | `circle.circle` | 全自主完成复杂任务 |

### 4.2 专注写作模式生命周期

```
进入: 快照 Dock 状态 → 隐藏全部 Dock → centerMode = .focusWriting
退出: 恢复快照状态 → centerMode = 之前模式
触发: 菜单 Cmd+Opt+Shift+E / ESC 退出
```

### 4.3 文档标注同步

```
用户编辑文档 → AnnotationParser 解析标注
→ DocumentChangeDetector 检测变更
→ (实时模式) 立即通知 Agent / (手动模式) 点击同步按钮
→ ChatManager 接收标注问题 → 增强到下一条消息
```

### 4.4 菜单快捷键体系

| 快捷键 | 功能 |
|--------|------|
| `Cmd+T` | 新建标签 |
| `Cmd+Shift+N` | 新建案件 |
| `Cmd+O` | 打开文件 |
| `Cmd+S` | 保存文档 |
| `Cmd+Opt+S` | 切换侧栏 |
| `Cmd+Opt+C` | 切换协作面板 |
| `Cmd+Opt+B` | 切换浏览器 |
| `Cmd+Opt+D` | 文档分屏模式 |
| `Cmd+Opt+Shift+E` | 专注写作模式 |
| `Cmd+Ctrl+F` | 全屏 |
| `Cmd+Enter` | 发送消息 |

---

## 五、无障碍设计 (Accessibility)

项目在无障碍方面有较完整的覆盖:

- **accessibilityLabel**: 几乎所有交互组件都有语义标签
- **accessibilityHint**: 补充操作说明
- **accessibilityValue**: 状态值 (如 Tab "活跃"/"未活跃")
- **accessibilityAddTraits**: `.isSelected`, `.isButton`, `.isHeader`, `.isStaticText`
- **accessibilityElement**: `.contain` / `.summaryElement`
- **Dynamic Type**: 使用 HIG 语义字体, 支持动态字号

---

## 六、设计亮点与优势

### 6.1 架构层面

1. **Dock 容器化设计** — 借鉴 Zed, 面板可扩展性强, 新增面板只需注册枚举值
2. **CenterMode 枚举** — 中心区切换干净利落, 避免 if-else 嵌套
3. **AppStateStore 单一数据源** — Combine 响应式, 状态可追踪
4. **ContentViewModifiers 抽象** — 将菜单/工具栏/文件导入逻辑从视图分离

### 6.2 视觉层面

1. **完整的 DesignTokens 系统** — 间距/圆角/字体/图标/颜色/阴影/动画全覆盖
2. **8pt 网格基准** — 间距一致性好
3. **双层颜色系统** — 系统色映射 + 业务语义色, 适配深色模式
4. **毛玻璃效果** — StatusBar/Sidebar/CaseWorkspace 使用 `.thickMaterial`
5. **消息气泡设计** — 用户/助手区分清晰, 描边透明度精细调节

### 6.3 交互层面

1. **三种 Flow 模式** — 适应不同专利代理场景
2. **文档标注同步** — 编辑器与 Agent 实时/手动双向联动
3. **Clarify 交互** — Agent 可主动询问, 用户单选/多选/自由输入
4. **专注写作模式** — 状态快照/恢复机制完善

---

## 七、问题与改进建议

### 7.1 架构问题

| # | 问题 | 严重度 | 建议 |
|---|------|--------|------|
| 1 | AppStateStore 存在 6 个 deprecated 旧变量, 迁移未完成 | 中 | 完成 Step 2 迁移, 清理死代码 |
| 2 | `DockPanel` 协议在 UI_DESIGN.md 中定义但未实现 | 中 | 实现协议, 统一面板行为 |
| 3 | `leftDockSection` 中 `caseWorkspace` 与 `caseList` 并列, 但 UI_DESIGN.md 规划的 `.folderTree` 面板缺失 | 低 | 补充 folderTree 面板或更新文档 |
| 4 | `TabManager` 使用 `nonisolated(unsafe)` observer, 存在并发隐患 | 中 | 迁移到 Combine `onReceive` |
| 5 | `ChatManager` 类型体量过大 (335 行), 承担消息/流式/clarify/文档同步多重职责 | 高 | 拆分为 MessageService + StreamService + ClarifyService |

### 7.2 视觉问题

| # | 问题 | 严重度 | 建议 |
|---|------|--------|------|
| 1 | 毛玻璃效果仅在 StatusBar/Sidebar 使用, 中心区缺少层次感 | 中 | 输入栏/消息列表区考虑 `.ultraThinMaterial` |
| 2 | 消息气泡缺少 Markdown 渲染, 纯文本展示 | 高 | 集成 Markdown 解析器 (如 Down/MarkdownUI) |
| 3 | TabBar 在 `TabStripContent` 中未使用, 实际 Tab 切换依赖侧边栏列表 | 中 | 明确 Tab 导航入口, 统一交互路径 |
| 4 | 空状态图标 `IconSize.emptyState` (40pt) 偏小, 视觉引导力不足 | 低 | 增大至 48-56pt |
| 5 | ChecklistView 使用 `AnyView` 类型擦除, 性能不佳 | 低 | 改用 `@ViewBuilder` 或 `some View` |
| 6 | 颜色硬编码散落 (如 `Color.blue.opacity(0.05)` 在多处重复) | 中 | 提取为 DesignTokens 语义色 |

### 7.3 交互问题

| # | 问题 | 严重度 | 建议 |
|---|------|--------|------|
| 1 | `CollaborationToggle` 按钮的 `action: {}` 为空, 无实际功能 | 高 | 接入 `rightDockVisible.toggle()` |
| 2 | `ToolManagerPopover` 的三个设置链接 `action` 均为空 | 高 | 接入实际设置页面跳转 |
| 3 | 文件拖拽仅通知 `dropFile`, 但无处理器接收 | 中 | 接入 DocumentWorkspace 加载逻辑 |
| 4 | `WindowStateRestoration` 已定义但未在 ContentView 中使用 | 中 | 挂载 `.withWindowRestoration()` |
| 5 | 窗口标题 `activeTabTitle` 始终为 "YunPat-Ai", 未随 Tab 变化 | 低 | 绑定活跃 Tab 标题 |
| 6 | 输入栏 `lineLimit(1...6)` 但无自动滚动, 长文本体验差 | 低 | 添加 ScrollViewReader 自动滚动 |

### 7.4 一致性问题

| # | 问题 | 严重度 | 建议 |
|---|------|--------|------|
| 1 | 部分 Picker 使用 `CornerRadius.xs` (4pt), 部分使用 `CornerRadius.sm` (6pt) | 低 | 统一为 `CornerRadius.sm` |
| 2 | 部分视图使用 `Color.blue` 直接引用, 部分使用 `Color.accentColor` | 中 | 统一使用 accentColor 或定义 `appBrandBlue` |
| 3 | 头像尺寸 `IconSize.avatar` (28pt) 小于 HIG 建议的 32pt | 低 | 考虑增大至 32pt |
| 4 | `statusBarHeight` 文档中写 32pt, 代码中为 34pt | 低 | 同步文档与代码 |

---

## 八、文件清单与职责

### 8.1 核心视图文件 (App/Views/)

| 文件 | 行数 | 职责 |
|------|------|------|
| `ContentView.swift` | 343 | 主窗口骨架, 三栏布局, 聊天区, 输入栏 |
| `ChatView.swift` | 458 | ChatManager + MessageBubble 消息气泡 |
| `TabStripContent.swift` | 403 | 顶部工具栏: 模型选择/流程模式/工具/协作 |
| `StatusBar.swift` | 170 | 三段式底部状态栏 |
| `CaseListSidebar.swift` | 209 | 左侧栏: 案件列表 + 筛选 + Tab 行 |
| `DocumentWorkspace.swift` | 181 | 底部 Dock: 文档编辑器 + 标注 |
| `CollaborationPanelView.swift` | 85 | 右侧栏: 协作审批面板 |
| `CaseWorkspaceView.swift` | 259 | 左侧栏: 案件工作区元数据 |
| `CaseGraphView.swift` | 143 | 右侧栏: 案件关系图 |
| `PatentBrowser.swift` | 272 | 中心区: 内嵌 WKWebView 专利浏览器 |
| `ClarifyOverlay.swift` | 140 | 聊天区: Agent 澄清询问覆盖层 |
| `ChecklistView.swift` | 69 | 聊天区: Agent 任务清单 |
| `EmptyStateView.swift` | 82 | 通用空状态组件 |
| `FolderTreeView.swift` | 225 | 递归文件目录树 |
| `MemoryAuditView.swift` | 329 | 记忆审计面板 (HSplitView) |

### 8.2 设计系统文件

| 文件 | 职责 |
|------|------|
| `DesignTokens.swift` | 间距/圆角/字体/图标/面板宽度/动画/阴影/语义色 |
| `Color+App.swift` | NSColor 映射 + 业务语义色 |
| `Tab.swift` | TabType/ChatTab/ClarifyRequestDisplay/ChatMessage 模型 |

### 8.3 状态管理文件

| 文件 | 职责 |
|------|------|
| `AppStateStore.swift` | 全局 Dock 状态 + 专注写作 + 撤销重做 |
| `ContentViewModifiers.swift` | 菜单事件 + 工具栏 + 文件导入 |
| `WindowStateRestoration.swift` | 窗口状态持久化 (未启用) |

---

## 九、总结

YunPat-Ai 桌面端 UI 设计整体水准较高, 具备以下特征:

**成熟度**: 设计系统完整 (DesignTokens 全覆盖), 布局架构清晰 (三 Dock + CenterMode), 状态管理统一 (AppStateStore 单源), 无障碍覆盖良好。

**专业适配**: 深度适配专利代理场景 — 三种 Agent Flow 模式、文档标注同步、专利浏览器内嵌、案件关系图、Clarify 交互、记忆审计。

**对标产品**: 明确借鉴 Zed Editor 的 Dock/Panel/StatusBar 架构, 同时保持 macOS 原生 HIG 规范。

**主要待改进项**:
1. 完成 Dock 系统迁移, 清理 6 个 deprecated 变量
2. 拆分 ChatManager 巨型类 (335 行 → 3 个 Service)
3. 补全空操作按钮 (CollaborationToggle / ToolManagerPopover)
4. 集成 Markdown 渲染提升消息可读性
5. 统一颜色引用方式, 减少硬编码

**迁移完成度评估**: UI_DESIGN.md 规划的 Step 1 (纯新增) 已完成, Step 2 (ContentView 重构) 进行中约 60%, Step 3 (StatusBar) 已完成。
