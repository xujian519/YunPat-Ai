# YunPat-Ai UI 设计规范

> 基于 Zed Editor 布局架构设计的 macOS 专利代理桌面端 UI 规范。
> 更新日期: 2026-07-04

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
┌─────────────────────────────────────────────────────────────────┐
│                       TabStripContent                            │  ← 顶部工具栏
│       [模型选择] [流程模式] [工具] [协作按钮]                     │
├──────┬──────────────────────────────────────────┬──────┬─────────┤
│      │                                          │      │         │
│      │                                          │      │         │
│ LEFT │            CENTER                        │ RIGHT│         │
│ DOCK │        (CenterMode)                      │ DOCK │         │
│      │                                          │      │         │
│  ┌──┐│  ┌────────────────────────────────┐      │  ┌──┐│         │
│  │案││  │                                │      │  │协││         │
│  │件││  │  Chat / Browser / FocusWrite   │      │  │作││         │
│  │列││  │                                │      │  │审││         │
│  │表││  │                                │      │  │批││         │
│  ├──┤│  │                                │      │  ├──┤│         │
│  │文││  │                                │      │  │案││         │
│  │件││  │                                │      │  │件││         │
│  │树││  │                                │      │  │图││         │
│  │  ││  │                                │      │  │谱││         │
│  └──┘│  └────────────────────────────────┘      │  └──┘│         │
│      │                                          │      │         │
├──────┴──────────────────────────────────────────┴──────┴─────────┤
│                       BOTTOM DOCK (Full Width)                   │  ← 全宽横条
│               [文档工作区 / 同步面板]                             │
├──────────────────────────────────────────────────────────────────┤
│              STATUS BAR (底部工具栏)                               │
│ [📁案件列表] [📁文件树] [📚知识库]        [🤝协作] [📄文档] [💻已连接] │
└──────────────────────────────────────────────────────────────────┘
```

### 2.1 视觉层次

| 层 | z-index | 内容 | 说明 |
|----|---------|------|------|
| 1 | 0 | HSplitView 主布局 | 三栏/Dock 容器 |
| 2 | 10 | Zoomed overlay | 专注写作层覆盖 |
| 3 | 20 | Sheet/Modal | 设置面板、向导 |
| 4 | 30 | Toast/通知 | 临时消息 |

---

## 3. Dock 系统规范

### 3.1 DockPosition 枚举

```swift
enum DockPosition: String, CaseIterable, Codable {
    case left    // 左侧 Dock: 案件列表、文件树、知识库
    case right   // 右侧 Dock: 协作审批、案件图谱
    case bottom  // 底部 Dock: 文档工作区 (全宽, Zed Full 模式)
}
```

### 3.2 CenterMode 枚举

```swift
enum CenterMode: String, CaseIterable, Codable {
    case chat         // 默认聊天模式
    case browser      // 专利浏览器模式
    case focusWriting // 专注写作模式 (隐藏所有 Dock)
}
```

### 3.3 可见性规则真值表

| CenterMode | leftDock | rightDock | bottomDock | StatusBar | TabStrip |
|------------|----------|-----------|------------|-----------|----------|
| `.chat`    | ✅ 受控   | ✅ 受控    | ✅ 受控     | ✅        | ✅       |
| `.browser` | ✅ 受控   | ✅ 受控    | ❌ 隐藏     | ✅        | ✅       |
| `.focusWriting` | ❌ 隐藏 | ❌ 隐藏 | ❌ 隐藏     | ❌ 隐藏   | ❌ 隐藏  |

**规则**:
- `browser` 模式下隐藏 Bottom Dock（浏览器需要垂直空间）
- `focusWriting` 隐藏全部装饰性 UI，仅显示 `DocumentWorkspace`
- 切换出 `focusWriting` 后恢复之前所有 Dock 的可见性状态

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
| 案件列表 | `.caseList` | `folder` | 240 | 200 | 默认活跃面板 |
| 文件树 | `.folderTree` | `tree` | 260 | 200 | 从旧 centerMode split 迁移 |
| 知识库 | `.knowledge` | `books.vertical` | 240 | 200 | 预留 |

#### Right Dock 面板

| 面板 | 枚举值 | SF Symbol | 默认宽度 | 最小宽度 |
|------|--------|-----------|---------|---------|
| 协作审批 | `.collaboration` | `checklist` | 280 | 240 |
| 案件图谱 | `.caseGraph` | `graph` | 280 | 240 |

#### Bottom Dock 面板

| 面板 | 枚举值 | SF Symbol | 默认高度 | 备注 |
|------|--------|-----------|---------|------|
| 文档工作区 | `.document` | `doc.text` | 280 | 默认活跃面板 |

---

## 4. StatusBar 规范

StatusBar 替换现有 `BottomToolbar`，采用三段式布局（类比 Zed StatusBar）。

### 4.1 三段式结构

```
┌──────────────────────────────────────────────────────────────────┐
│ Left Section          │ Center Section       │ Right Section      │
│ [面板图标按钮组]       │ (预留状态信息)       │ [Dock toggle] [状态] │
│                        │                      │                     │
│ 📁案  📁树  📚知       │                      │ 🤝协  📄文  💻已连接  │
└──────────────────────────────────────────────────────────────────┘
```

### 4.2 Left Section — 面板切换

- **显示**: Left Dock 各面板的图标按钮
- **行为**: 点击切换 `leftDockActivePanel`
- **高亮**: 活跃面板按钮使用 `Color.statusRunning`，非活跃使用 `Color.groupBackground`
- **分组**: 面板之间紧贴，无分隔线；面板组与中心区间有 `Divider`

### 4.3 Right Section — Dock Toggle + 状态

| 组件 | 类型 | SF Symbol | 行为 |
|------|------|-----------|------|
| 协作 toggle | 开关按钮 | `checklist` | `rightDockVisible.toggle()` |
| 文档 toggle | 开关按钮 | `doc.text` | `bottomDockVisible.toggle()` |
| 连接状态 | 指示器 | `circle.fill` + 文本 | 只读显示 |

### 4.4 与 Zed 的关键差异

| 维度 | Zed | YunPat-Ai |
|------|-----|-----------|
| StatusBar 位置 | 窗口底部 | 底部（同 Zed） |
| 面板切换定位 | 左右端各一组 | 左段集中式面板切换 |
| Toggle 按钮 | 仅 toggle dock | toggle + 面板级切换 |
| 高度 | 动态 | 固定 32pt (`PanelWidth.statusBarHeight`) |

---

## 5. 状态管理规范

### 5.1 AppStateStore (单一数据源)

```swift
@MainActor
final class AppStateStore: ObservableObject {
    // ---- Dock 系统 ----
    @Published var leftDockVisible: Bool = true
    @Published var rightDockVisible: Bool = false
    @Published var bottomDockVisible: Bool = false
    @Published var centerMode: CenterMode = .chat

    // ---- 面板选择 ----
    @Published var leftDockActivePanel: LeftDockPanel = .caseList
    @Published var rightDockActivePanel: RightDockPanel = .collaboration

    // ---- 专注写作状态快照 ----
    private var focusWritingRestoreState: (Bool, Bool, Bool, CenterMode)? = nil
}
```

### 5.2 废除的旧状态

| 旧变量 | 新等效 | 说明 |
|--------|--------|------|
| `sidebarCollapsed` | `!leftDockVisible` | 反向映射 |
| `collaborationVisible` | `rightDockVisible` | 直接映射 |
| `browserVisible` | `centerMode == .browser` | 模式切换 |
| `documentSplitVisible` | 废除 | 文件树移入 Left Dock |
| `folderTreeVisible` | 废除 | 死代码 |
| `caseGraphMode` | `rightDockActivePanel == .caseGraph` | 面板切换 |
| `focusWritingMode` | `centerMode == .focusWriting` | 模式切换 |

---

## 6. Panel 协议规范

### 6.1 DockPanel 协议

```swift
protocol DockPanel: View {
    /// 面板唯一标识
    associatedtype ID: RawRepresentable<String>
    static var panelID: ID { get }

    /// 所属 Dock
    static var dockPosition: DockPosition { get }

    /// SF Symbol 图标名
    static var icon: String { get }

    /// 面板标题（用于 tooltip 和 accessibility）
    static var title: String { get }

    /// 默认/最小尺寸
    static var defaultWidth: CGFloat { get }
    static var minWidth: CGFloat { get }

    /// 是否默认打开（初次启动时）
    static var startsOpen: Bool { get }
}
```

### 6.2 现有面板映射

| 旧视图 | 新面板 ID | Dock | 宽度 | 图标 |
|--------|----------|------|------|------|
| `CaseListSidebar` | `.caseList` | Left | 240 | `folder` |
| `FolderTreeView` | `.folderTree` | Left | 260 | `tree` |
| (预留) | `.knowledge` | Left | 240 | `books.vertical` |
| `CollaborationPanel` | `.collaboration` | Right | 280 | `checklist` |
| `CaseGraphView` | `.caseGraph` | Right | 280 | `graph` |
| `DocumentWorkspace` | `.document` | Bottom | 280h | `doc.text` |

---

## 7. 尺寸约束

### 7.1 DesignTokens 增量

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
    static let flowPicker: CGFloat = 240
    static let settingsWidth: CGFloat = 520
    static let settingsHeight: CGFloat = 480

    // 新增
    static let bottomDockMinHeight: CGFloat = 180
    static let bottomDockIdealHeight: CGFloat = 280
    static let statusBarHeight: CGFloat = 32
}
```

### 7.2 窗口默认尺寸

```swift
// YunPatApp.swift
.defaultSize(width: 1200, height: 800)
```

布局分配合计（无 Dock 打开时）:
- Left Dock (240) + Center (可伸缩) + Right Dock (0) = 窗口宽度
- Left Dock (240) + Center + Right Dock (280) = 窗口宽度
- Bottom Dock 从底部占用 280pt

---

## 8. 过渡动画规范

### 8.1 动画常量

```swift
enum AnimationDuration {
    static let fast: CGFloat = 0.15      // 按钮 hover
    static let normal: CGFloat = 0.2     // 面板切换
    static let slow: CGFloat = 0.25      // Dock 显隐
    static let spring: CGFloat = 0.35    // 专注写作模式切换
}
```

### 8.2 Dock 显隐动画

```swift
// HSplitView 自动处理动画（通过 frame 变化）
.frame(minWidth: ..., idealWidth: ...)
.animation(.easeInOut(duration: AnimationDuration.slow), value: leftDockVisible)

// Bottom Dock 使用 transition
.animation(.easeInOut(duration: AnimationDuration.slow), value: bottomDockVisible)
```

### 8.3 面板切换动画

```swift
// 同一 Dock 内换面板使用 opacity 过渡
.transition(.opacity.combined(with: .move(edge: .trailing)))
.animation(.easeInOut(duration: AnimationDuration.normal), value: rightDockActivePanel)
```

---

## 9. 迁移路径

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

### Step 3 ⏳ BottomToolbar → StatusBar

- [ ] 重构 `BottomToolbar` 为三段式 StatusBar
- [ ] 左段: Left Dock 面板切换按钮组
- [ ] 右段: Right/Bottom Dock toggle
- [ ] 废弃旧 `BottomToolbar.swift`
- [ ] 连接状态常驻右段

---

## 10. 废弃清理清单

| 文件 | 废弃内容 | 清理时机 |
|------|---------|---------|
| `BottomToolbar.swift:7` | `@Binding var folderTreeVisible: Bool` | Step 3 |
| `BottomToolbar.swift:18-19` | folder 按钮 | Step 3 |
| `ContentView.swift:12` | `@State folderTreeVisible` | Step 2 |
| `ContentView.swift:81` | `folderTreeVisible: $folderTreeVisible` | Step 2 |
| `ContentView.swift:13` | `@State caseGraphMode` | Step 2 |
| `ContentView.swift:115` | `caseGraphMode` 条件判断 | Step 2 |
| `ContentViewModifiers.swift:8-14` | 所有 `@Binding` 旧状态 | Step 2 |

---

## 11. 参考

- [Zed Dock](https://github.com/zed-industries/zed/blob/master/crates/workspace/src/dock.rs) — Dock 容器与 Panel trait
- [Zed PaneGroup](https://github.com/zed-industries/zed/blob/master/crates/workspace/src/pane_group.rs) — 递归二分树布局
- [Zed StatusBar](https://github.com/zed-industries/zed/blob/master/crates/workspace/src/status_bar.rs) — 三段式状态栏
- [Zed Panel](https://github.com/zed-industries/zed/blob/master/crates/panel/src/panel.rs) — Panel trait 扩展
- [Apple HIG — Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
