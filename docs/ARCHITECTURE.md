---
status: 生效 (2026-06-29)
范围: YunPatCore / YunPatNetworking / YunPatDesktop / YunPatPlugins / YunPatSandbox / App
验证: SwiftLint 命名后缀规则 + CI Gate
---

# YunPat-Ai 架构规则与命名约定

## 一、概念架构（六层）

代码按**概念层**归属，通过命名后缀（而非目录）区分。物理目录按**领域/能力**组织。

```
┌─────────────────────────────────────────────────────┐
│  Models — 纯数据，无逻辑，无副作用，无单例             │
├─────────────────────────────────────────────────────┤
│  Services — 业务逻辑，actor/struct，不可被 UI 观察     │
├─────────────────────────────────────────────────────┤
│  Managers — UI 状态，@MainActor @Observable          │
├─────────────────────────────────────────────────────┤
│  Views — SwiftUI，按 feature 分文件夹                │
├─────────────────────────────────────────────────────┤
│  Networking — HTTP 服务器/客户端，模型路由            │
├─────────────────────────────────────────────────────┤
│  Storage — SQLite/JSON 持久化                       │
│  Tools — MCP 工具定义与注册                          │
│  Identity — 加密密钥与访问控制                       │
│  Utils — 跨领域工具函数（无领域知识）                  │
└─────────────────────────────────────────────────────┘
```

## 二、物理目录组织（领域驱动）

代码实际按**能力领域**分目录，概念层归属通过命名后缀区分：

```
Packages/YunPatCore/Sources/YunPatCore/
├── Capability/     — Services: CapabilityRegistry, CapabilityDefinition, ToolDefinition
├── Context/        — Services: ContextEngine, CompactionWatermark, TokenEstimator
├── Desktop/        — Services: FileOperationLog, FileSnapshotStore
├── Hooks/          — Services: AgentHook, HooksService
├── Knowledge/      — Services: WikiAdapter, RuleEngine, FactExtractor, EvaluationEngine 等
│                   — Models: WikiTypes, StructuredFacts, ApplicableRules 等
├── Loop/           — Services: AgentLoopEngine, PatentLoopEngine, PatentToolLoop 等
│                   — Models: LoopState, LoopResult, ApprovalRequest 等
├── Memory/         — Services: MemoryEngine, MemoryConsolidator, MemoryWritePath 等
│                   — Storage: MemoryStore, MemoryDatabase
├── Models/Chat/    — Models: SessionSource, ChatSessionData
├── Patent/         — Services: FactBlackboard, LegalStateMachine, ChecklistEngine 等
├── Privacy/        — Services: PrivacyFilter, PathSecurity 等
├── Quality/        — Services: PatentRubric, FactMarker, TabooDetector 等
├── Runtime/        — Services: RuntimeConfig, CoopScheduler, AgentMetrics
├── Skill/          — Services: SkillManager, SkillParser
├── SSR/            — Services: SSRGuard
├── Storage/        — Storage: CaseDatabase, StorageConverger, DegradedStore
├── SystemPrompt/   — Services: SystemPromptService
├── Tools/          — Tools: ToolResponse, ToolErrorCode + Docs/
├── Trace/          — Services: TraceCollector, TraceStore
├── Utilities/      — Utils: Bits, RandGenerator, SyncWrapper
└── Utils/          — Utils: DateParser

App/Views/
├── ChatView, ContentView, Tab, TabBar, BottomToolbar 等
├── Settings/       — Views: ProviderSettingsView, SkillSettingsView 等
└── DocumentWorkspace, AnnotationParser, PatentBrowser 等
```

**原则**：概念层归属（Model/Service/Manager/View）通过**命名后缀**验证，物理位置通过**领域归属**判断。

## 三、分层规则

### Models — 纯数据
- 只能是 `struct`/`enum`，**禁止** `class`。
- **禁止** `@Published`、`ObservableObject`、`@Observable`。
- **禁止** `static let shared` 或任何单例模式。
- 允许 `Codable`、`Sendable`。
- 放置位置：`Models/` 目录（跨领域通用） 或相应领域目录内（如 `Knowledge/WikiTypes.swift`）。

### Services — 业务逻辑
- 并发工作用 `actor`；纯函数用 `stateless struct`。
- **禁止** conform `ObservableObject`/`@Observable`。
- **禁止** 直接驱动 UI。
- 命名后缀：`Service`（通用服务）、`Engine`（主循环/引擎）。

### Managers — UI 状态
- **必须** `@MainActor` + `@Observable`（首选）或 `ObservableObject`。
- 持有 Views 绑定的 `@Published`/`@Observable` 属性。
- 命名后缀：`Manager`。
- 放置位置：`App/Views/` 或独立 `Managers/` 目录。

### Views — SwiftUI
- 按 feature 分组：`Views/Settings/`、`Views/`（主视图）。
- 仅在某 feature 内有效的 view 放对应 feature 目录。

### Networking — 网络层
- 独立 SPM 包 `YunPatNetworking`。
- **禁止** 包含 UI 逻辑或持久化逻辑。

### Storage — 持久化
- JSON 文件 → 命名后缀 `Store`
- SQLite → 命名后缀 `Database`

### Utils — 工具函数
- 纯函数，无领域知识。
- **禁止** import 本项目其他模块。
- 放置位置：`Utilities/` 或 `Utils/`。

## 四、命名约定总表

| 模式 | 命名后缀 | 示例 |
|---|---|---|
| Observable UI 状态 | `Manager` | `ChatManager`, `TabManager` |
| Actor 业务逻辑 | `Service` / `Engine` | `MemoryEngine`, `PatentToolLoop` |
| 无状态逻辑 | `Service` / — | `SkillParser`, `VectorSearch` |
| JSON/文件持久化 | `Store` | `MemoryStore`, `LLMMemoryStore` |
| SQLite 持久化 | `Database` | `MemoryDatabase`, `CaseDatabase` |
| SwiftUI View | `View` | `ChatView`, `SkillSettingsView` |
| 测试文件 | `Tests` | `PatentLoopEngineTests`, `MemoryEngineTests` |

## 五、当前合规状态

### 已修复
| 文件 | 原类型 | 现类型 |
|---|---|---|
| `ContextEngine.swift` | `@unchecked Sendable` class | `actor` ✅ |
| `CapabilityRegistry.swift` | `@unchecked Sendable` class | `actor` ✅ |

### 待修复
| 文件 | 当前类型 | 应迁移为 |
|---|---|---|
| `SystemPromptService.swift` | `@unchecked Sendable` class | `actor` |
| `SkillParser.swift` | class | `struct`（无状态解析器） |
| `VaultObserver.swift` | class | `actor` |
| `HooksService.swift` | class | `actor` |
| `FactBlackboard.swift` | class (NSLock) | `actor` |
| `LegalStateMachine.swift` | class (NSLock) | `actor` |

> 迁移原则：新代码 100% 合规；旧代码在有充分测试覆盖和回归验证时逐项迁移。

## 六、验证

- SwiftLint 规则（`.swiftlint.yml`）强制命名后缀：`Service`/`Engine`/`Manager`/`Store`/`Database`/`View`。
- CI Gate：新代码违反规则 → 构建失败。
- PR Review：架构层归属不合理 → 要求修改。
