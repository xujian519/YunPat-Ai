# YunPat-Ai Apple HIG 合规性审阅报告

> 审阅日期: 2026-07-08
> 审阅范围: `App/` 目录全部 SwiftUI/AppKit 视图文件
> 对照标准: Apple Human Interface Guidelines (macOS 15+)
> 综合评分: 6.9 / 10

---

## 一、合规现状总览

| 维度 | 评分 | 状态 |
|------|------|------|
| 视觉设计 | 8/10 | 良好 |
| 字体排版 | 9/10 | 优秀 |
| 无障碍 | 6/10 | 待改进 |
| 导航模式 | 5/10 | 差距明显 |
| 窗口管理 | 5/10 | 差距明显 |
| 交互反馈 | 7/10 | 尚可 |
| 菜单命令 | 8/10 | 良好 |
| 深色模式 | 7/10 | 尚可 |

---

## 二、已合规项 (做得好的部分)

### 2.1 字体系统 — HIG 语义字体全覆盖 (9/10)

项目在 `DesignTokens.swift` 中定义了完整的 HIG 语义字体枚举，全部使用 SwiftUI 语义字体而非硬编码字号，天然支持 Dynamic Type:

```swift
enum FontStyle {
    static let largeTitle: Font = .largeTitle
    static let title: Font = .title
    static let headline: Font = .headline
    static let body: Font = .body
    static let callout: Font = .callout
    static let caption: Font = .caption
    // ...
}
```

这完全符合 HIG "Use semantic fonts" 的要求，用户在系统偏好中调整字号时界面会自动响应。

### 2.2 颜色系统 — 系统色映射 + 双层语义 (8/10)

`Color+App.swift` 正确使用 `NSColor` 系统色映射，确保深色模式自动适配:

```swift
static let appTextPrimary = Color(nsColor: .labelColor)
static let appSurfacePrimary = Color(nsColor: .controlBackgroundColor)
static let appSeparator = Color(nsColor: .separatorColor)
```

HIG 要求 "Use system colors" 以确保深色模式自动适配 — 这部分做得很好。

### 2.3 菜单栏与快捷键体系 (8/10)

`YunPatApp.swift` 的 `commands` 实现了标准 macOS 菜单结构:
- App Info / File / Edit / View / Window / Help 六大菜单组
- 快捷键覆盖: Cmd+T (新建标签)、Cmd+Shift+N (新建案件)、Cmd+O (打开)、Cmd+S (保存)
- 视图切换: Cmd+Opt+L (侧栏)、Cmd+Opt+C (协作)、Cmd+Opt+B (浏览器)
- 使用 `CommandGroup(replacing:)` 和 `CommandMenu` 正确注册

### 2.4 SF Symbols 统一图标系统 (8/10)

全程使用 SF Symbols，在 `DesignTokens.swift` 定义了 `IconSize` 枚举统一尺寸:
- toolbar (16pt) / sidebar (14pt) / inlineSmall (12pt) / emptyState (40pt)
- 符合 HIG "Use SF Symbols" 要求

### 2.5 Settings Scene 正确使用 (7/10)

使用 SwiftUI 的 `Settings` scene 而非自定义窗口:
```swift
Settings {
    ModernSettingsView(modelRouter: appState.modelRouter)
        .frame(minWidth: 720, minHeight: 520)
}
```
符合 macOS 设置窗口规范。

### 2.6 间距系统 — 8pt 网格 (8/10)

`Spacing` 枚举以 8pt 为基准单位，定义了从 2pt 到 48pt 的完整阶梯，符合 HIG 间距一致性要求。

### 2.7 空状态设计 (7/10)

`EmptyStateView` 提供统一的空状态组件，包含图标、标题、副标题和操作按钮，符合 HIG "Empty States" 指引。

### 2.8 窗口基础配置 (7/10)

```swift
.windowResizability(.contentMinSize)
.defaultSize(width: 1200, height: 800)
.windowToolbarStyle(.unifiedCompact)
```

窗口可调整性、默认尺寸、工具栏样式配置合理。

---

## 三、关键差距项 (需改进)

### P0 — 必须修复

#### 3.1 未使用 NavigationSplitView

**现状**: `ContentView` 使用 `HStack` + 自定义 `ResizableDivider` 实现三栏布局。

**HIG 要求**: macOS 应用应使用 `NavigationSplitView` 实现多栏导航，以获得:
- 原生侧边栏外观（毛玻璃、圆角、vibrancy）
- 系统一致的拖拽调整行为
- 侧边栏折叠/展开的原生动画
- 与 `NavigationStack` 联动的 push/pop 导航

**影响**: 侧边栏外观与系统原生应用（如 Mail、Notes、Finder）不一致，缺少原生毛玻璃效果和系统级行为。

**建议**:
```swift
NavigationSplitView(columnVisibility: $visibility) {
    ProjectListSidebar(tabManager: tabManager)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
} content: {
    centerContent
} detail: {
    detailContent
}
.navigationSplitViewStyle(.balanced)
```

#### 3.2 自定义 TopBar 未使用 .toolbar API

**现状**: `ContentView.topBar` 是自定义 `HStack`，未使用 SwiftUI 的 `.toolbar` 修饰符和 `ToolbarItem`。

**影响**:
- `.windowToolbarStyle(.unifiedCompact)` 已配置但无实际 ToolbarItem
- 缺少原生工具栏外观（材质、间距、按钮样式）
- 无法支持工具栏自定义
- 不支持 Touch Bar

**建议**: 将 `TopModuleButton` 和面包屑迁移到 `.toolbar`:
```swift
.toolbar {
    ToolbarItemGroup(placement: .navigation) {
        breadcrumb
    }
    ToolbarItemGroup(placement: .primaryAction) {
        ForEach(TopModule.allCases) { module in
            Button(action: { switchToModule(module) }) {
                Label(module.rawValue, systemImage: module.icon)
            }
        }
    }
}
```

#### 3.3 外观模式设置未生效

**现状**: `ModernSettingsView` 有外观选择器（跟随系统/浅色/深色），`appearanceMode` 存储到 `@AppStorage`，但从未在视图中应用 `preferredColorScheme`。

**影响**: 用户切换外观设置后无任何效果，功能完全失效。

**建议**: 在 `WindowGroup` 的根视图上应用:
```swift
ContentView(...)
    .preferredColorScheme(appearanceMode.colorScheme)
```

### P1 — 应尽快修复

#### 3.4 未尊重 accessibilityReduceMotion 偏好

**现状**: 多处使用 `.animation()`、`.symbolEffect(.pulse)`、`withAnimation` 等动画，但未检查 `@Environment(\.accessibilityReduceMotion)`。

**HIG 要求**: 当用户在系统偏好中开启"减少动态效果"时，应用应禁用或简化动画。

**影响**: 影响前庭觉敏感用户的可用性。

**建议**:
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

// 使用条件动画
if reduceMotion {
    // 无动画或仅淡入淡出
} else {
    withAnimation(.easeInOut(duration: AnimationDuration.slow)) { ... }
}
```

#### 3.5 侧边栏行使用 onTapGesture 替代 Button

**现状**: `SidebarTabRow` 使用 `.onTapGesture` 处理点击，而非 `Button`。

**影响**:
- 键盘用户无法通过 Tab 键聚焦和 Enter 激活
- VoiceOver 用户无法正确识别为可操作元素
- 丢失原生按钮的 hover/press 状态

**建议**: 改用 `Button` + `.buttonStyle(.plain)`:
```swift
Button(action: { tabManager.activeTabID = tab.id }) {
    // 行内容
}
.buttonStyle(.plain)
```

#### 3.6 自定义按钮缺少键盘焦点环

**现状**: 大量自定义 `.buttonStyle(.plain)` 按钮未实现 `focusable()` 或 `.focusEffectDisabled(false)`，键盘 Tab 导航时无可见焦点环。

**HIG 要求**: 所有可交互元素必须有清晰的焦点指示器。

**影响**: 键盘导航用户无法识别当前聚焦元素。

**建议**: 对关键交互按钮添加 `.focusable()` 并确保系统默认焦点环可见，或自定义 `focusEffect`:
```swift
.focusEffectDisabled(false)
```

#### 3.7 部分按钮小于 HIG 44pt 最小命中区域

**现状**: `HitTarget.small = 28pt`，多个工具栏按钮使用此尺寸。

**HIG 要求**: macOS 交互元素最小命中区域为 44pt x 44pt (虽比 iOS 的 44pt 灵活，但仍建议保持)。

**建议**: 即使视觉上较小，也应通过 `.contentShape` 扩展命中区域到 44pt:
```swift
Image(systemName: icon)
    .frame(width: 28, height: 28)
    .contentShape(Rectangle().inset(by: -8)) // 扩展到 44pt
```

### P2 — 重要改进

#### 3.8 大量 .buttonStyle(.plain) 丢失原生状态反馈

**现状**: `ToolButton`、`TopModuleButton`、`LauncherButton`、`SidebarTabRow` 等组件全部使用 `.buttonStyle(.plain)` + 自定义背景。

**影响**:
- 丢失原生 hover/press/disabled 视觉状态
- 不一致的交互反馈模式
- 增加 QA 成本

**建议**: 在需要自定义外观的场景，仍应使用系统按钮样式作为基础:
```swift
// 优先使用
.buttonStyle(.bordered)
.buttonStyle(.borderless)
// 仅在确需完全自定义时使用 .plain，但保留 .hover 状态
```

#### 3.9 自定义 Tab 条未使用原生窗口标签

**现状**: `TabBar` 是自定义 HStack + TabButton，位于 ContentView 内部。

**HIG 建议**: macOS 应用应考虑使用原生窗口标签 (Window Tabbing)，让用户通过系统标签管理多文档。

**影响**: 与 Safari、Finder、TextEdit 等原生应用的标签行为不一致。

#### 3.10 NSCursor 手动管理

**现状**: `ResizableDivider` 手动调用 `NSCursor.resizeLeftRight.set()` 和 `NSCursor.arrow.set()`。

**问题**: 
- 在 `.onHover` 中设置光标可能在特定情况下不恢复
- 与 SwiftUI 声明式范式不一致

**建议**: 考虑使用 `NSViewRepresentable` 包装 `NSCursor.resizeLeftRight.push()/pop()`，或使用 SwiftUI 的 `.cursor` (macOS 15+ 如可用)。

#### 3.11 缺少 Cmd+数字 模块切换快捷键

**现状**: 顶部 6 个模块 (智能体/文件/技能/路由/记忆/常驻) 无键盘快捷键切换。

**HIG 惯例**: macOS 应用通常用 Cmd+1 ~ Cmd+9 切换主要视图/标签。

**建议**:
```swift
ForEach(Array(TopModule.allCases.enumerated()), id: \.element.id) { idx, module in
    Button(module.rawValue) { switchToModule(module) }
        .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: .command)
}
```

### P3 — 日常改进

#### 3.12 Popover 固定尺寸不适配大字号

**现状**: Popover 使用 `.frame(width: 240, height: 320)` 等固定尺寸。

**影响**: 当用户开启大字号辅助功能时，Popover 内容可能被裁切。

**建议**: 使用 `minWidth` / `maxWidth` 替代固定 `width`，或使用 `fixedSize(horizontal: false, vertical: false)`。

#### 3.13 设置侧栏选中样式不符合原生

**现状**: `ModernSettingsView` 的选中行使用 `Color.white` 文字 + `Color.accentColor` 背景。

**问题**: macOS 原生设置侧栏使用 `sidebarSelection` 系统色，文字保持原色而非变白。

**建议**: 使用系统提供的选择样式:
```swift
.listStyle(.sidebar)
// 或使用 .tint 控制选中色
```

#### 3.14 缺少 Haptic Feedback

**现状**: 无任何 `NSHapticFeedbackManager` 调用。

**HIG 建议**: 在显著状态变化或操作完成时提供触觉反馈（如发送消息、标签切换）。

#### 3.15 缺少 .help 工具提示覆盖

**现状**: 部分按钮有 `.help()`，但许多自定义按钮（如 `ToolButton`、`SuggestionPill`）缺少。

#### 3.16 窗口标题未实时更新

**现状**: `windowTitle` 在 `.task` 和 `.onChange(of: activeTab?.title)` 中更新，但初始标题始终为 "YunPat-Ai"，切换 Tab 后才更新。

#### 3.17 缺少 Quick Look 集成

**现状**: 文件浏览器和专利浏览器中无 Quick Look 预览支持。

**影响**: 对专利 PDF/文档密集型应用，Quick Look 是 macOS 用户的强预期功能。

### P4 — 按需评估

#### 3.18 未使用 DocumentGroup 文档模型

**现状**: 应用以自定义 Tab 管理文档，未使用 `DocumentGroup` 或 `ReferenceFileDocument`。

**影响**: 缺少系统级文档管理（版本浏览、自动保存、iCloud 同步）。

**评估**: 对于 AI 代理应用，这可能是有意为之的架构决策，但值得评估是否可部分引入。

#### 3.19 拖放仅窗口级

**现状**: `.onDrop` 挂在 `WindowGroup` 根视图上，无特定 drop zone 视觉提示。

#### 3.20 窗口恢复不完整

**现状**: `WindowStateRestoration` 仅保存/恢复窗口 frame，不含 Tab 列表、活跃 Tab、滚动位置等。

#### 3.21 缺少 Services 菜单 / Share 集成

**现状**: 无 `NSServicesProvider` 注册，无 Share 按钮集成。

---

## 四、维度详细分析

### 4.1 导航模式 (5/10)

| HIG 要求 | 当前状态 | 差距 |
|----------|---------|------|
| 使用 NavigationSplitView | 自定义 HStack | P0 |
| 侧边栏原生毛玻璃 | 仅使用 `.listStyle(.sidebar)` | 需配合 NavigationSplitView |
| push/pop 导航栈 | 无 NavigationStack | 中心区无层级导航 |
| 面包屑导航 | 有自定义面包屑 | 非系统组件但可接受 |
| 模块间快捷键切换 | 缺少 Cmd+1~6 | P2 |

### 4.2 窗口管理 (5/10)

| HIG 要求 | 当前状态 | 差距 |
|----------|---------|------|
| 原生工具栏 (.toolbar) | 自定义 HStack TopBar | P0 |
| 窗口标签 (Tabbing) | 自定义 Tab 条 | P2 |
| 窗口恢复 | 仅 frame，无 Tab 状态 | P3 |
| 最小尺寸约束 | `.contentMinSize` 已设置 | 合规 |
| 全屏支持 | `.toggleFullScreen` 已实现 | 合规 |
| 多窗口支持 | `WindowGroup` 已支持 | 合规 |

### 4.3 无障碍 (6/10)

| HIG 要求 | 当前状态 | 差距 |
|----------|---------|------|
| accessibilityLabel 覆盖 | 19 个文件有覆盖 | 良好 |
| accessibilityHint | 部分覆盖 | 需补全 |
| accessibilityValue | Tab 状态有 | 良好 |
| accessibilityAddTraits | isSelected/isButton/isHeader | 良好 |
| reduceMotion 尊重 | 未检查 | P1 |
| Dynamic Type | 使用语义字体 | 合规 |
| 键盘导航 | 部分 onTapGesture 阻断 | P1 |
| 焦点环可见 | 自定义按钮缺失 | P1 |
| 最小命中区域 | 部分 28pt | P2 |

### 4.4 交互反馈 (7/10)

| HIG 要求 | 当前状态 | 差距 |
|----------|---------|------|
| hover 状态 | 自定义 onHover 实现 | 良好但非原生 |
| press 状态 | .plain 按钮丢失 | P2 |
| context menu | 有实现 | 合规 |
| 拖拽光标 | NSCursor 手动管理 | P2 |
| 动画一致性 | AnimationDuration 统一 | 良好 |
| Haptic Feedback | 缺失 | P3 |

### 4.5 深色模式 (7/10)

| HIG 要求 | 当前状态 | 差距 |
|----------|---------|------|
| 系统色自动适配 | NSColor 映射 | 良好 |
| 外观切换 | 设置项存在但未生效 | P0 |
| 阴影自适应 | ShadowPair 双套 | 良好 |
| 描边强度自适应 | colorScheme 判断 | 良好 |

---

## 五、优先级修复路线图

### 第一阶段: 紧急修复 (P0)

1. **应用外观模式设置** — 在根视图添加 `.preferredColorScheme(appearanceMode.colorScheme)`
2. **迁移到 NavigationSplitView** — 替换 HStack + ResizableDivider 为 NavigationSplitView
3. **迁移到 .toolbar API** — 将 TopBar 内容迁移到 ToolbarItem

### 第二阶段: 无障碍修复 (P1)

4. **尊重 reduceMotion** — 添加环境变量检查，条件化动画
5. **将 onTapGesture 改为 Button** — 侧边栏行、工具按钮等
6. **添加焦点环** — 关键交互按钮确保键盘焦点可见
7. **扩展命中区域** — 28pt 按钮扩展到 44pt

### 第三阶段: 一致性改进 (P2)

8. **减少 .buttonStyle(.plain) 滥用** — 优先使用系统样式
9. **评估原生窗口标签** — 考虑使用系统 Tabbing API
10. **添加模块切换快捷键** — Cmd+1~6
11. **修复 NSCursor 管理** — 使用更安全的光标管理方式

### 第四阶段: 细节打磨 (P3-P4)

12. Popover 自适应尺寸
13. 设置侧栏选中样式
14. 添加 Haptic Feedback
15. 补全 .help 工具提示
16. Quick Look 集成
17. 评估 DocumentGroup 模型

---

## 六、总结

YunPat-Ai 桌面端在**设计系统层面**（间距、字体、颜色、图标、阴影、动画）表现出色，DesignTokens 体系完整且系统色映射正确。但在**原生组件使用**层面存在明显差距 — 最核心的问题是绕过了 NavigationSplitView 和 .toolbar API，大量使用自定义 HStack 布局和 .buttonStyle(.plain)，导致丢失了 macOS 原生的交互行为、视觉反馈和无障碍特性。

**最高 ROI 改进**: 将 ContentView 迁移到 NavigationSplitView + .toolbar，可一次性解决导航、工具栏、侧边栏外观、系统一致性多个问题。

**最低成本改进**: 在根视图添加 `.preferredColorScheme(appearanceMode.colorScheme)`，一行代码修复失效的外观设置功能。
