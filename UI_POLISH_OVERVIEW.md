# YunPat-Ai UI 设计打磨 · 概览

> UI Designer 对 macOS 客户端（SwiftUI）视觉层的一次聚焦打磨。
> 目标：激活已定义但闲置的设计令牌系统、统一卡片/表面视觉语言、消除硬编码颜色。

## 核心问题（审计发现）

1. **高程系统「死代码」**：`DesignTokens.AppShadow`（sm/md/lg/glow）已定义但**从未被任何视图引用**，导致所有卡片（`StatCard`、`ProviderStatusCard`、欢迎页建议卡、设置卡片、记忆/常驻卡片）全部渲染为「扁平卡片」，仅靠 `background + cornerRadius`，缺少层次与投影。
2. **硬编码状态色散落**：多处使用 `Color.secondary.opacity(0.1)`、`Color.green.opacity(0.08)`、`Color.accentColor.opacity(0.08)`、`Color.primary.opacity(0.06)` 以及原始 `Color(NSColor.controlBackgroundColor)`，绕过令牌系统，明暗两套主题下行为不一致。
3. **语义状态色未被复用**：`ProviderStatusCard` 直接写 `.green/.orange/.red`，未用已有的 `Color.statusSuccess/Warning/Destructive`。

## 改动清单

### 1. 新建统一表面系统 `App/Views/SurfaceModifiers.swift`
- `appCard(elevation:cornerRadius:)` —— 统一「表面背景 + 圆角 + 发丝描边 + 高程投影」，真正启用 `AppShadow`。
- `appSurface(cornerRadius:)` —— 嵌入式次级表面（仅描边、无外投影）。

### 2. 新增软状态令牌 `App/Views/Color+App.swift`
- `appStatusNeutralSoft`、`appStatusDestructiveSoft`、`appAccentSoft`，替代散落的 opacity 硬编码。

### 3. 应用 elevation + 令牌一致性
| 视图 | 改动 |
|---|---|
| `StatCard` | 改用 `appCard(elevation:.sm)` |
| `ProviderStatusCard` | `appCard` + 语义状态色（`statusSuccess/Warning/Destructive`） |
| `RoutingDashboardView` 策略区 | `appCard` |
| `PromptCard`（欢迎页） | `appCard` + 鼠标 hover 高亮态 |
| `ModernSettingsView` 设置卡片 / 侧栏 / 内容区 | `appCard`；去掉原始 `NSColor` |
| `MemoryEntryRow` | `appCard` |
| `AlwaysOnDashboardView` 两张卡片 | `appCard` |
| `ProjectListSidebar` / `CaseListSidebar` 流程徽章 | `appStatusNeutralSoft` |
| `TabStripContent` 路由/模型指示器 + 模型选中高亮 | `appStatusSuccessSoft` / `appAccentSoft` |

### 刻意保留（不强行令牌化）
- 图表/关系着色：`CaseGraphView`、`MemoryAuditView`（按关系/层级语义着色）。
- 树形缩进引导线：`FolderTreeView`（结构性用途，非状态/表面）。

## 设计收益
- 卡片获得一致的高程投影与发丝描边，明暗主题下层次统一、可读性与「精致感」提升。
- 颜色来源收敛到令牌系统，后续主题/品牌色调整只需改一处。
- 交互态（建议卡 hover、模型选中高亮）获得清晰的视觉反馈。

## 验证
- 通过 `swift build --product YunPatAi` 编译校验（见对话构建结果）。
