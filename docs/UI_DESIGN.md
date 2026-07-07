# YunPat-Ai UI 设计规范

> 基于 Zed Editor 布局架构设计的 macOS 专利代理桌面端 UI 规范。
> 更新日期: 2026-07-07

---

## 1. 设计哲学

借鉴 Zed Editor 的布局核心思想，提炼六大原则：

| # | 原则 | Zed 来源 | YunPat-Ai 应用 |
|---|------|----------|---------------|
| 1 | **Dock 容器化** | 左/右/底三 Dock，每个容纳多面板 | 三 Dock 分别承载案件/协作/文档面板 |
| 2 | **单 bool 控显隐** | `Dock::set_open(bool)` | Dock 可见性 = 一个 `@Published` 属性 |
| 3 | **StatusBar 为唯一入口** | `PanelButtons` 挂在 StatusBar 左右端 | 底部工具栏按钮严格按 Dock 分组 |
| 4 | **Panel 协议抽象** | `trait Panel` 定义尺寸/图标/位置 | `DockPanel` 协议统一面板行为 |
| 5 | **中心为 PaneGroup** | 递归二分树 + flex 布局 | 中心区 `CenterMode` 枚举，无嵌套 if-else |
| 6 | **递归而非正交** | Dock 可见性由 DockPosition 定义，而非多个正交 bool | 消灭 7 个散落 @State，归并为 3 Dock + 1 CenterMode |

---

## 2. 整体布局架构

```
┌──────────────────────────────────────────────────────────────────┐
│                       TopModuleBar                                │  ← 顶部主导航栏
│   [YunPat-Ai / 智能体]    [✨智能体] [📁文件] [⭐技能] [📊路由]   │
│                          [🧠记忆] [🔊常驻]                       │
├──────────────────────────────────────────────────────────────────┤
│ NavigationSplitView (三栏) — 由 leftDockVisible 控制列可见性      │
├──────┬──────────────────────────────────────────┬─────────────────┤
│      │                                          │                 │
│ LEFT │            CENTER (CenterMode)            │  RIGHT DOCK     │
│ SIDEB│                                          │                 │
│  ┌──┐│  ┌────────────────────────────────┐      │  ┌──────────┐   │
│  │项││  │  Chat / Browser / FocusWrite   │      │  │ 协作审批  │   │
│  │目││  │  FileBrowser / SkillGallery    │      │  │ 案件图谱  │   │
│  │列││  │  Routing / Memory / AlwaysOn   │      │  │ 成本仪表  │   │
│  │表││  │                                │      │  │ 记忆审计  │   │
│  │  ││  │                                │      │  │ 工具审计  │   │
│  └──┘│  └────────────────────────────────┘      │  └──────────┘   │
│      │                                          │                 │
├──────┴──────────────────────────────────────────┴─────────────────┤
│                       BOTTOM DOCK (Full Width)                    │  ← 全宽横条
│                     [文档工作区 / 同步面板]                         │
├──────────────────────────────────────────────────────────────────┤
│                         STATUS BAR                                 │
│     [📁项目列表]              [🤝协作] [📊成本] [🧠记忆审计] [💻已连接]│
└──────────────────────────────────────────────────────────────────┘
```

### 2.1 视觉层次

| 层 | z-index | 内容 | 说明 |
|----|---------|------|------|
| 1 | 0 | NavigationSplitView 主布局 | 三栏/Dock 容器 |
| 2 | 10 | Zoomed overlay | 专注写作层覆盖 |
| 3 | 20 | Sheet/Modal | 设置面板、向导 |
| 4 | 30 | Toast/通知 | 临时消息 |

---

## 3. Dock 系统规范

### 3.1 DockPosition 枚举

```swift
enum DockPosition: String, CaseIterable, Codable {
    case left    // 左侧 Dock: 项目列表
    case right   // 右侧 Dock: 协作审批、案件图谱、成本仪表盘、记忆审计、工具审计
    case bottom  // 底部 Dock: 文档工作区 (全宽, Zed Full 模式)
}
```

### 3.2 CenterMode 枚举

```swift
enum CenterMode: String, CaseIterable, Codable {
    case chat         // 默认聊天模式
    case browser      // 专利浏览器模式
    case focusWriting // 专注写作模式 (隐藏所有 Dock)
    case files        // 文件浏览
    case skills       // 技能库
    case routing      // 路由仪表盘
    case memory       // 记忆管理
    case alwaysOn     // 后台常驻任务
}
```

### 3.3 可见性规则真值表

| CenterMode | leftDock | rightDock | bottomDock | StatusBar | Toolbar |
|------------|----------|-----------|------------|-----------|---------|
| `.chat`    | ✅ 受控   | ✅ 受控    | ✅ 受控     | ✅        | ✅      |
| `.browser` | ✅ 受控   | ✅ 受控    | ❌ 隐藏     | ✅        | ✅      |
| `.focusWriting` | ❌ 隐藏 | ❌ 隐藏 | ❌ 隐藏     | ❌ 隐藏   | ❌ 隐藏 |
| `.files`   | ✅ 受控   | ✅ 受控    | ✅ 受控     | ✅        | ✅      |
| `.skills`  | ✅ 受控   | ✅ 受控    | ✅ 受控     | ✅        | ✅      |
| `.routing` | ✅ 受控   | ✅ 受控    | ✅ 受控     | ✅        | ✅      |
| `.memory`  | ✅ 受控   | ✅ 受控    | ✅ 受控     | ✅        | ✅      |
| `.alwaysOn`| ✅ 受控   | ✅ 受控    | ✅ 受控     | ✅        | ✅      |

**规则**:
- `browser` 模式下隐藏 Bottom Dock（浏览器需要垂直空间）
- `focusWriting` 隐藏全部装饰性 UI，仅显示 `DocumentWorkspace`
- 切换出 `focusWriting` 后恢复之前所有 Dock 的可见性状态
- `.files` / `.skills` / `.routing` / `.memory` / `.alwaysOn` 的可见性规则与 `.chat` 相同（所有 Dock 受控显示）

### 3.4 专注写作生命周期

```
进入 focusWriting:
  1. 快照当前 dockVisible 状态到 focusWritingRestoreState
  2. leftDockVisible = false, rightDockVisible = false, bottomDockVisible = false
  3. centerMode = .focusWriting

退出 focusWriting (ESC / 按钮):
  1. 从 focusWritingRestoreState 恢复三个 dockVisible
  2. centerMode = 之前模式 (默认 .chat)
```

### 3.5 面板注册表

#### Left Dock 面板

| 面板 | 枚举值 | SF Symbol | 默认宽度 | 最小宽度 | 备注 |
|------|--------|-----------|---------|---------|------|
| 项目列表 | `.projectList` | `folder` | 240 | 200 | 统一面板，替代原案件列表/文件树/知识库 |

#### Right Dock 面板

| 面板 | 枚举值 | SF Symbol | 默认宽度 | 最小宽度 |
|------|--------|-----------|---------|---------|
| 协作审批 | `.collaboration` | `checklist` | 280 | 240 |
| 案件图谱 | `.caseGraph` | `graph` | 280 | 240 |
| 成本仪表盘 | `.costDashboard` | `chart.pie` | 300 | 260 |
| 记忆审计 | `.memoryAudit` | `brain.head.profile` | 320 | 260 |
| 工具审计 | `.toolAudit` | `hammer` | 360 | 280 |

#### Bottom Dock 面板

| 面板 | 枚举值 | SF Symbol | 默认高度 | 备注 |
|------|--------|-----------|---------|------|
| 文档工作区 | `.document` | `doc.text` | 280 | 默认活跃面板 |

---

## 4. TopModule 导航系统

顶部主导航栏，与 CenterMode 联动切换中心区内容。

### 4.1 TopModule 枚举

```swift
enum TopModule: String, CaseIterable, Codable, Identifiable {
    case agent    = "智能体"
    case files    = "文件"
    case skills   = "技能"
    case routing  = "路由"
    case memory   = "记忆"
    case alwaysOn = "常驻"
}
```

### 4.2 模块与 CenterMode 映射

| TopModule | CenterMode 映射 | 图标 | 视图组件 |
|-----------|---------------|------|---------|
| `.agent` | `.chat` | `sparkles` | Chat 界面 |
| `.files` | `.files` | `folder` | FileBrowserView |
| `.skills` | `.skills` | `wand.and.stars` | SkillGalleryView |
| `.routing` | `.routing` | `chart.pie` | RoutingDashboardView |
| `.memory` | `.memory` | `brain.head.profile` | MemoryDashboardView |
| `.alwaysOn` | `.alwaysOn` | `waveform` | AlwaysOnDashboardView |

### 4.3 TopModuleBar 视图

位于窗口顶部，包含：
- **左侧**: 面包屑导航 `YunPat-Ai / 当前模块名`
- **中间**: 六个模块图标按钮，活跃态高亮
- **右侧**: 打开文件按钮 + 设置齿轮按钮

高度固定为 `PanelWidth.topBarHeight` (48pt)，使用 `.thickMaterial` 背景。
点击模块按钮同时更新 `appState.topModule` 和 `appState.centerMode`。

---

## 5. StatusBar 规范

StatusBar 替换现有 `BottomToolbar`，采用三段式布局（类比 Zed StatusBar）。

### 5.1 三段式结构

```
┌──────────────────────────────────────────────────────────────────┐
│ Left Section          │ Center Section       │ Right Section      │
│ [面板图标按钮组]       │ (预留状态信息)       │ [Dock toggle] [状态] │
│                        │                      │                     │
│ 📁项目列表              │                      │ 🤝协  📊成本  🧠记忆审计  💻已连接│
└──────────────────────────────────────────────────────────────────┘
```

### 5.2 Left Section — 面板切换

- **显示**: Left Dock 各面板的图标按钮
- **行为**: 点击切换 `leftDockActivePanel`
- **高亮**: 活跃面板按钮使用 `Color.statusRunning`，非活跃使用 `Color.groupBackground`
- **分组**: 面板之间紧贴，无分隔线；面板组与中心区间有 `Divider`

### 5.3 Right Section — Dock Toggle + 状态

| 组件 | 类型 | SF Symbol | 行为 |
|------|------|-----------|------|
| 协作 toggle | 开关按钮 | `checklist` | `rightDockVisible.toggle()` |
| 文档 toggle | 开关按钮 | `doc.text` | `bottomDockVisible.toggle()` |
| 连接状态 | 指示器 | `circle.fill` + 文本 | 只读显示 |

### 5.4 与 Zed 的关键差异

| 维度 | Zed | YunPat-Ai |
|------|-----|-----------|
| StatusBar 位置 | 窗口底部 | 底部（同 Zed） |
| 面板切换定位 | 左右端各一组 | 左段集中式面板切换 |
| Toggle 按钮 | 仅 toggle dock | toggle + 面板级切换 |
| 高度 | 动态 | 固定 34pt (`PanelWidth.statusBarHeight`) |

---

## 6. 状态管理规范

### 6.1 AppStateStore (单一数据源)

```swift
@MainActor
public final class AppStateStore: ObservableObject, @unchecked Sendable {
    public static let shared = AppStateStore()

    // ---- Dock 系统 ----
    @Published public var leftDockVisible: Bool = true
    @Published public var rightDockVisible: Bool = false
    @Published public var bottomDockVisible: Bool = false
    @Published public var centerMode: CenterMode = .chat
    @Published public var topModule: TopModule = .agent

    // ---- 面板选择 ----
    @Published public var leftDockActivePanel: LeftDockPanel = .projectList
    @Published public var rightDockActivePanel: RightDockPanel = .collaboration

    // ---- 专注写作状态快照 ----
    struct FocusWritingSnapshot {
        var leftVisible: Bool
        var rightVisible: Bool
        var bottomVisible: Bool
        var mode: CenterMode
    }
    var focusWritingRestoreState: FocusWritingSnapshot?
}
```

### 6.2 已废除的旧状态（审计确认全部移除）

| 旧变量 | 新等效 | 移除状态 |
|--------|--------|---------|
| `sidebarCollapsed` | `!leftDockVisible` | ✅ 已移除 |
| `collaborationVisible` | `rightDockVisible` | ✅ 已移除 |
| `browserVisible` | `centerMode == .browser` | ✅ 已移除 |
| `documentSplitVisible` | 废除（文件树移入 Left Dock） | ✅ 已移除 |
| `folderTreeVisible` | 废除（死代码） | ✅ 已移除 |
| `caseGraphMode` | `rightDockActivePanel == .caseGraph` | ✅ 已移除 |
| `focusWritingMode` | `centerMode == .focusWriting` | ✅ 已移除 |
| `folderTreeVisible` (ContentView @State) | 已迁移至 AppStateStore | ✅ 已移除 |
| `caseGraphMode` (ContentView @State) | 已迁移至 AppStateStore | ✅ 已移除 |

---

## 7. Panel 协议规范

### 7.1 DockPanel 协议

> **注意**: `DockPanel` 协议在最终实现中**未作为正式协议**实现。LeftDockPanel 和 RightDockPanel 是纯 String 枚举，面板选择通过 `@Published var leftDockActivePanel` / `rightDockActivePanel` 配合 `switch` 语句在 `ContentView` 中分发。`DockPosition` 枚举保留在 `DesignTokens.swift` 中供布局参考。

### 7.2 现有面板映射

| 旧视图 | 新面板 ID | Dock | 宽度 | 图标 |
|--------|----------|------|------|------|
| `CaseListSidebar` (废弃) | `.projectList` | Left | 240 | `folder` |
| `CollaborationPanel` | `.collaboration` | Right | 280 | `checklist` |
| `CaseGraphView` | `.caseGraph` | Right | 280 | `graph` |
| (新增) | `.costDashboard` | Right | 300 | `chart.pie` |
| (新增) | `.memoryAudit` | Right | 320 | `brain.head.profile` |
| (新增) | `.toolAudit` | Right | 360 | `hammer` |
| `DocumentWorkspace` | `.document` | Bottom | 280h | `doc.text` |

---

## 8. 新增视图指南

### 8.1 中心区视图 (CenterMode)

| 视图 | 文件路径 | CenterMode | 描述 |
|------|---------|-----------|------|
| `FileBrowserView` | `App/Views/Workspace/FileBrowserView.swift` | `.files` | 文件浏览器，左侧 FolderTreeView + 右侧 DocumentWorkspace |
| `SkillGalleryView` | `App/Views/Workspace/SkillGalleryView.swift` | `.skills` | 技能库浏览与 SKILL.md 编辑，HSplitView 双栏 |
| `RoutingDashboardView` | `App/Views/Workspace/RoutingDashboardView.swift` | `.routing` | 路由策略 Dashboard，含 StatCard 指标、模型选择、提供商状态 |
| `MemoryDashboardView` | `App/Views/Workspace/MemoryDashboardView.swift` | `.memory` | 五层记忆架构仪表盘，含层级选择与最近条目 |
| `AlwaysOnDashboardView` | `App/Views/Workspace/AlwaysOnDashboardView.swift` | `.alwaysOn` | 后台常驻任务面板，AlwaysOnCard 网格布局 + 快捷动作 |

### 8.2 共享组件

| 组件 | 文件路径 | 描述 |
|------|---------|------|
| `StatCard` | `App/Views/Workspace/StatCard.swift` | 通用统计卡片，含标题/数值/图标/趋势/颜色 |

### 8.3 导航与侧边栏

| 组件 | 文件路径 | 描述 |
|------|---------|------|
| `TopModuleBar` | `App/Views/Navigation/TopModuleBar.swift` | 顶部主导航栏，面包屑 + 6 个模块按钮 |
| `ProjectListSidebar` | `App/Views/Project/ProjectListSidebar.swift` | 统一项目列表面板，替代原案件列表 + 文件树 + 知识库 |

### 8.4 设置

| 组件 | 文件路径 | 描述 |
|------|---------|------|
| `ModernSettingsView` | `App/Views/Settings/ModernSettingsView.swift` | 设置面板，左侧分类侧栏 + 右侧内容区 |

---

## 9. 尺寸约束

### 9.1 DesignTokens 增量

```swift
enum PanelWidth {
    // 现有保留
    static let sidebarMin: CGFloat = 200   // → left dock
    static let sidebarIdeal: CGFloat = 240
    static let sidebarMax: CGFloat = 300
    static let collaborationMin: CGFloat = 240  // → right dock
    static let collaborationIdeal: CGFloat = 280
    static let collaborationMax: CGFloat = 360
    static let folderTreeMin: CGFloat = 200
    static let folderTreeIdeal: CGFloat = 260
    static let caseWorkspaceMin: CGFloat = 260
    static let caseWorkspaceIdeal: CGFloat = 300
    static let costDashboardMin: CGFloat = 260
    static let costDashboardIdeal: CGFloat = 300
    static let memoryAuditMin: CGFloat = 260
    static let memoryAuditIdeal: CGFloat = 320
    static let toolAuditMin: CGFloat = 280
    static let toolAuditIdeal: CGFloat = 360
    static let flowPicker: CGFloat = 240
    static let welcomeMax: CGFloat = 640
    static let suggestionCardMin: CGFloat = 200
    static let settingsWidth: CGFloat = 520
    static let settingsHeight: CGFloat = 480

    // Bottom Dock
    static let bottomDockMinHeight: CGFloat = 180
    static let bottomDockIdealHeight: CGFloat = 280

    // StatusBar / TopBar
    static let statusBarHeight: CGFloat = 34
    static let topBarHeight: CGFloat = 48
}
```

### 9.2 窗口默认尺寸

```swift
// YunPatApp.swift
.defaultSize(width: 1200, height: 800)
```

布局分配合计（无 Dock 打开时）:
- Left Dock (240) + Center (可伸缩) + Right Dock (0) = 窗口宽度
- Left Dock (240) + Center + Right Dock (280) = 窗口宽度
- Bottom Dock 从底部占用 280pt

---

## 10. 过渡动画规范

### 10.1 动画常量

```swift
enum AnimationDuration {
    static let fast: CGFloat = 0.15      // 按钮 hover
    static let normal: CGFloat = 0.2     // 面板切换
    static let slow: CGFloat = 0.25      // Dock 显隐
    static let spring: CGFloat = 0.35    // 专注写作模式切换
}
```

### 10.2 Dock 显隐动画

```swift
// NavigationSplitView 自动处理动画（通过 frame 变化）
.frame(minWidth: ..., idealWidth: ...)
.animation(.easeInOut(duration: AnimationDuration.slow), value: leftDockVisible)

// Bottom Dock 使用 transition
.animation(.easeInOut(duration: AnimationDuration.slow), value: bottomDockVisible)
```

### 10.3 面板切换动画

```swift
// 同一 Dock 内换面板使用 opacity 过渡
.transition(.opacity.combined(with: .move(edge: .trailing)))
.animation(.easeInOut(duration: AnimationDuration.normal), value: rightDockActivePanel)
```

---

## 11. 迁移路径

### Step 1 ✅ 纯新增（无破坏）

> 当前阶段

- [x] 新增 `DockPosition` 枚举到 `DesignTokens.swift`
- [x] 新增 `CenterMode` 枚举到 `DesignTokens.swift`
- [x] 新增 `LeftDockPanel` / `RightDockPanel` 枚举到 `AppStateStore.swift`
- [x] 新增 `AppStateStore` dock 状态属性
- [x] 创建 `docs/UI_DESIGN.md`

### Step 2 🔄 ContentView 重构

- [ ] ContentView 改用 AppStateStore 统一状态，废除本地 7 个 @State
- [ ] `ContentViewModifiers` 改用新状态引用
- [ ] 专注写作生命周期实现（状态快照/恢复）
- [ ] `folderTreeVisible` 绑定移除 → 文件树纳入 Left Dock

### Step 3 ✅ BottomToolbar → StatusBar

- [x] 重构 `BottomToolbar` 为三段式 StatusBar
- [x] 左段: Left Dock 面板切换按钮组
- [x] 右段: Right/Bottom Dock toggle
- [x] 废弃旧 `BottomToolbar.swift`（已删除）
- [x] 连接状态常驻右段

---

## 12. 废弃清理状态

| 废弃项 | 状态 | 说明 |
|--------|------|------|
| `BottomToolbar.swift` | ✅ 已删除 | 完全替换为 StatusBar |
| `@Binding var folderTreeVisible` | ✅ 已迁移 | 已纳入 AppStateStore 应用状态面板 |
| `@State folderTreeVisible` (ContentView) | ✅ 已迁移 | 已删除 |
| `@State caseGraphMode` (ContentView) | ✅ 已迁移 | 已删除 |

---

## 13. 参考

- [Zed Dock](https://github.com/zed-industries/zed/blob/master/crates/workspace/src/dock.rs) — Dock 容器与 Panel trait
- [Zed PaneGroup](https://github.com/zed-industries/zed/blob/master/crates/workspace/src/pane_group.rs) — 递归二分树布局
- [Zed StatusBar](https://github.com/zed-industries/zed/blob/master/crates/workspace/src/status_bar.rs) — 三段式状态栏
- [Zed Panel](https://github.com/zed-industries/zed/blob/master/crates/panel/src/panel.rs) — Panel trait 扩展
- [Apple HIG — Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
