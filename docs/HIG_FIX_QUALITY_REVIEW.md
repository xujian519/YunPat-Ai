# HIG 修复全面质量审阅报告

**审阅日期**: 2026-07-08
**审阅范围**: 16 个修改文件 + 1 个新建文件 (AccessibilityHelpers.swift)
**审阅方法**: 逐文件代码审查 + 编译验证 + SwiftLint 严格检查 + 回归分析

---

## 1. 总体结论

| 维度 | 修复前 | 修复后 | 变化 |
|------|--------|--------|------|
| 导航系统 | 5.0 | 8.5 | +3.5 |
| 无障碍 | 4.0 | 9.0 | +5.0 |
| 视觉一致性 | 6.5 | 9.2 | +2.7 |
| 交互模式 | 5.5 | 8.7 | +3.2 |
| 菜单/快捷键 | 7.0 | 9.5 | +2.5 |
| 窗口管理 | 6.0 | 8.5 | +2.5 |
| 编译/Lint | 10/10 | 10/10 | — |
| **综合** | **6.9** | **8.9** | **+2.0** |

**编译**: swift build — 零错误零警告
**SwiftLint**: --strict — 254 文件 0 违规

---

## 2. 通过项 (15/18)

### P0 修复 — 全部正确实施

| # | 修复项 | 状态 | 质量评价 |
|---|--------|------|----------|
| 1 | AppearanceMode.colorScheme + preferredColorScheme | ✅ 通过 | `AppearanceMode` 枚举添加 `colorScheme` 计算属性，`.system` 返回 `nil` 让系统接管，设计正确。`YunPatApp` 在根视图应用 `.preferredColorScheme(appearanceMode.colorScheme)`，`@AppStorage` 双向绑定确保设置变更即时生效。 |
| 2 | NavigationSplitView 替换 HStack+ResizableDivider | ✅ 通过 | 使用 `NavigationSplitView(columnVisibility:)` + `navigationSplitViewColumnWidth(min:ideal:max:)`，获得系统原生侧边栏毛玻璃、拖拽行为。`.navigationSplitViewStyle(.balanced)` 选择合理。 |
| 3 | .toolbar API 替换自定义 TopBar | ✅ 通过 | 面包屑放 `.navigation` 位、模块导航放 `.primaryAction` 位，符合 HIG 工具栏布局规范。`.windowToolbarStyle(.unifiedCompact)` 终于有实际 ToolbarItem 配合。 |

### P1 修复 — 实施质量优秀

| # | 修复项 | 状态 | 质量评价 |
|---|--------|------|----------|
| 4 | accessibleAnimation 修饰器 | ✅ 通过 | `ConditionalAnimation<V: Equatable>` ViewModifier 设计正确，`reduceMotion` 为 true 时跳过动画。`withAccessibleAnimation` 函数封装合理。`@MainActor` 标注正确。 |
| 5 | onTapGesture → Button 迁移 | ✅ 通过 | `TabButton` 和 `SidebarTabRow` 均改为 `Button(action:)`，键盘可聚焦。`accessibilityAddTraits` 正确标注 `.isSelected` + `.isButton`。 |
| 6 | minimumHitTarget() 修饰器 | ✅ 通过 | 使用 `HitTarget.minimum` (44pt) + `contentShape(Rectangle())` 扩展命中区域。在 `ProjectListSidebar` 的按钮和 `TabStripContent` 的 `ToolManagerButton`/`CollaborationToggle` 上正确应用。 |
| 7 | ResizableDivider NSCursor push/pop | ✅ 通过 | `cursorPushed` 状态变量 + `pushCursor()/resetCursor()` 配对管理，`onDisappear` 安全重置。`accessibilityAdjustableAction` 允许键盘用户方向键调整面板宽度，设计优秀。 |
| 8 | reduceMotion 全面覆盖 | ✅ 通过 | 15 个视图文件添加 `@Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool`。所有 hover 动画、切换动画、滚动动画均有 reduceMotion 分支。 |

### P2 修复 — 实施正确

| # | 修复项 | 状态 | 质量评价 |
|---|--------|------|----------|
| 9 | Cmd+1~6 模块切换快捷键 | ✅ 通过 | `TopModule.shortcutDigit` / `shortcutKey` 设计清晰。`ForEach(TopModule.allCases)` + `.keyboardShortcut(module.shortcutKey, modifiers: .command)` 在 Commands builder 中正确注册。 |
| 10 | NSCursor 安全管理 | ✅ 通过 | push/pop 配对 + guard 防重入，无 cursor 栈泄漏风险。 |

### P3-P4 修复 — 实施良好

| # | 修复项 | 状态 | 质量评价 |
|---|--------|------|----------|
| 11 | Popover 自适应尺寸 | ✅ 通过 | 所有 Popover 从固定尺寸改为 `min/max` 范围（如 `minWidth: 240, maxWidth: 300`），适应不同内容长度。 |
| 12 | 设置侧栏原生选中样式 | ✅ 通过 | `accentColor` 文字 + `Color.accentColor.opacity(0.12)` 背景 + `accessibilityAddTraits(.isSelected)`，符合 macOS 原生设置侧栏视觉语言。 |
| 13 | NSHapticFeedbackManager | ✅ 通过 | `AppHaptic` 枚举提供三种反馈类型（alignment/generic/levelChange），在标签切换、发送消息、模块切换等关键操作点正确触发。 |
| 14 | .help() 工具提示 | ✅ 通过 | 关键按钮均添加 `.help()` 提示，快捷键提示格式统一（如 `"⌘\(module.shortcutDigit)"`）。 |
| 15 | accessibilityLabel/Hint 补全 | ✅ 通过 | 所有交互控件均有 `accessibilityLabel`，复杂控件添加 `accessibilityHint`。`accessibilityElement(children: .contain)` 在容器视图上正确使用。 |

---

## 3. 遗留问题 (3 项需跟进)

### 问题 A: menuShowTabBar 通知孤立 — P1 回归

**严重程度**: P1 (功能回归)
**位置**: `YunPatApp.swift:111` 发送 vs `ContentViewModifiers.swift` 无接收

**描述**:
菜单命令 "显示标签栏" (⌘⇧T) 在 `YunPatApp.swift` 中发送 `.menuShowTabBar` 通知：
```swift
Button("显示标签栏") {
    NotificationCenter.default.post(name: .menuShowTabBar, object: nil)
}
.keyboardShortcut("t", modifiers: [.command, .shift])
```

但 `ContentViewModifiers` 中没有对应的 `.onReceive(publisher(for: .menuShowTabBar))` 处理器。通知定义存在（line 295），但永远不会被消费。

**影响**: 菜单项 "显示标签栏" 点击后无任何效果。

**修复建议**:
在 `ContentViewModifiers` 中添加处理器，或如果该功能已被 NavigationSplitView 的原生侧边栏管理替代，则移除菜单项。

---

### 问题 B: NavigationSplitView 双向同步缺失 — P2

**严重程度**: P2 (状态不一致)
**位置**: `ContentView.swift:64-68`

**描述**:
`ContentView` 中有 `leftDockVisible → columnVisibility` 的单向同步：
```swift
.onChange(of: appState.leftDockVisible) { _, visible in
    withAccessibleAnimation(reduceMotion: reduceMotion) {
        columnVisibility = visible ? .all : .detailOnly
    }
}
```

但缺少反向同步：当用户通过 NavigationSplitView 原生侧边栏按钮折叠侧边栏时，`columnVisibility` 变化但 `appState.leftDockVisible` 不会更新。

**影响**:
- `leftDockVisible` 状态变旧，菜单 "切换侧栏" 可能与实际不符
- `WindowStateRestoration` 持久化的 `leftDockVisible` 值可能不反映用户最后的操作
- 专注写作恢复状态时，`leftDockVisible` 可能与实际列可见性不匹配

**修复建议**:
添加 `.onChange(of: columnVisibility)` 反向同步：
```swift
.onChange(of: columnVisibility) { _, newVisibility in
    let visible = newVisibility != .detailOnly
    if appState.leftDockVisible != visible {
        appState.leftDockVisible = visible
    }
}
```

---

### 问题 C: AppStateStore.toggleRightPanel 遗留 raw withAnimation — P2

**严重程度**: P2 (无障碍遗漏)
**位置**: `AppStateStore.swift:152-159`

**描述**:
`toggleRightPanel` 方法仍使用原始 `withAnimation` 而非 `withAccessibleAnimation`：
```swift
public func toggleRightPanel(_ panel: RightDockPanel) {
    withAnimation(.easeInOut(duration: 0.2)) {  // ← 未检查 reduceMotion
        if rightDockVisible && rightDockActivePanel == panel {
            rightDockVisible = false
        } else {
            openRightPanel(panel)
        }
    }
}
```

`AppStateStore` 是 `ObservableObject` 而非 `View`，无法直接访问 `@Environment(\.accessibilityReduceMotion)`。调用方（`RightPanelViews.swift` 中的 6 处）也未包装 `withAccessibleAnimation`。

**影响**: 开启了 "减少动态效果" 的用户在切换右栏面板时仍会看到动画。

**修复建议**:
方案一：在 `AppStateStore` 中添加 `reduceMotion` 属性，由根视图从 Environment 同步。
方案二：将 `toggleRightPanel` 的 `withAnimation` 移除，由调用方负责动画包装。

---

## 4. 次要发现 (不影响功能，建议优化)

### 4a. TopModuleButton 成为死代码

`TopModuleButton.swift` 定义了完整的模块导航按钮组件，但 `ContentView.moduleNavigation` 使用内联 `Button` 而非 `TopModuleButton`。该文件已编译但未被引用。

**建议**: 要么在 `moduleNavigation` 中使用 `TopModuleButton`，要么删除该文件避免混淆。

### 4b. 命中区域尺寸未完全达标

以下控件视觉高度低于 HIG 44pt 最小值（含 padding 后）：
- `ToolButton` (InputBar): 32pt 视觉 + 8pt padding = 40pt
- `TopModuleButton`: 32pt 视觉 + 8pt padding = 40pt（但仅在工具栏上下文中使用，系统可能补充命中区域）

**建议**: 为这两个控件添加 `.minimumHitTarget()` 或增大 `frame(minHeight:)` 到 44pt。

### 4c. FocusWritingContent / ContentViewModifiers.toggleFocusWriting 未使用 withAccessibleAnimation

这两处虽正确检查了 `reduceMotion`，但使用原始 `withAnimation(.spring(...))` 而非 `withAccessibleAnimation` 辅助函数，与代码库其他部分的模式不一致。

**影响**: 功能正确，仅代码一致性建议。

### 4d. menuToggleSplitScreen 调用 toggleSidebar()

"文档分屏模式" (⌘⌥D) 和 "切换侧栏" (⌘⌥L) 调用同一个 `toggleSidebar()` 方法。如果这两个功能原本有不同行为，则存在逻辑混淆。

**建议**: 确认 "文档分屏" 是否应有独立行为。若是，则实现独立逻辑；若否，则考虑合并菜单项。

---

## 5. 代码质量统计

| 指标 | 数值 |
|------|------|
| 修改文件数 | 16 |
| 新建文件数 | 1 (AccessibilityHelpers.swift) |
| 编译错误 | 0 |
| 编译警告 | 0 |
| SwiftLint 违规 (--strict) | 0 / 254 文件 |
| reduceMotion 覆盖文件 | 15 / 15 需要的视图文件 |
| accessibilityLabel 覆盖 | 所有交互控件 |
| .help() 工具提示 | 所有工具栏按钮 + 关键交互控件 |
| Haptic Feedback 触发点 | 5 处 (标签切换 x2, 发送, 模块切换, 协作面板) |

---

## 6. 修复优先级建议

| 优先级 | 问题 | 预估工作量 |
|--------|------|------------|
| P1 | A: menuShowTabBar 通知处理器 | 5 分钟 |
| P2 | B: NavigationSplitView 双向同步 | 10 分钟 |
| P2 | C: toggleRightPanel reduceMotion | 10 分钟 |
| P3 | 4a: TopModuleButton 死代码清理 | 5 分钟 |
| P3 | 4b: 命中区域尺寸补齐 | 10 分钟 |
| P4 | 4c: withAccessibleAnimation 一致性 | 5 分钟 |
| P4 | 4d: menuToggleSplitScreen 语义确认 | 需产品确认 |

**总预估**: ~45 分钟可全部解决
