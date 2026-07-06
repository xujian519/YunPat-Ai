# YunPat-Ai — Agent Guide

macOS 桌面端专利代理人 AI 智能体。Swift 6 + SwiftUI + AppKit，macOS 15.5+，Apple Silicon only。

## 快速命令

```bash
# 构建 & 单个包测试
swift build --package-path Packages/YunPatCore
swift test  --package-path Packages/YunPatCore  # 支持指定 -s <TestTarget>

# 分档测试（CI 等效）
swift scripts/run-tiered-tests.swift t0       # 纯本地（秒级）
swift scripts/run-tiered-tests.swift t0t1     # 本地 + 软依赖
swift scripts/run-tiered-tests.swift all      # 全量（含网络 API）

# 代码质量
swiftlint --strict                            # 强制命名后缀规则
# swift-format 通过 swift format 调用（配置 .swift-format）

# 工具注册表同步（注册逻辑变更后必跑）
swift scripts/sync-plugin-registry.swift

# 构建 App bundle
bash scripts/package-app.sh                  # 产出 .build/YunPatAi.app
```

## 包结构

| 包 | 用途 | 是否在根 Package.swift |
|---|---|---|
| `YunPatNetworking` | 模型路由 (OpenAI/Anthropic/DeepSeek/GLM) + Keychain | ✅ |
| `YunPatCore` | AgentLoop / 知识库 / 记忆 / 专利引擎 / 隐私过滤 / 桌面工具 | ✅ |
| `PatentClient` | Google Patents + PSS 客户端 (依赖 SwiftSoup) | ✅ |
| `YunPatPlugins` | 插件系统 (ClaimDrafting/Infringement/MCP 等) | ✅ |
| `YunPatDesktop` | 桌面自动化 (AppleScript/AXorcist/Shell) | ✅ |
| `YunPatSandbox` | 沙箱 Provider | ✅ |

全部 6 个包均可执行目标调用。App entrypoint: `App/YunPatApp.swift`。

## 六层架构规则（SwiftLint 强制执行）

架构规则见 `docs/ARCHITECTURE.md`，SwiftLint 通过 `custom_rules` 强制命名后缀：
- `Manager` — UI 状态 (`@MainActor @Observable`)
- `Service`/`Engine` — 业务逻辑 (`actor`)
- `Store` — JSON 持久化
- `Database` — SQLite
- `View` — SwiftUI 视图

**特例**：`ContextEngine.swift` / `CapabilityRegistry.swift` / `SystemPromptService.swift` 目前是 `@unchecked Sendable` class，计划迁为 `actor`。新代码必须合规。

## CI 与影响面检测

CI (`ci.yml`) 三级自动评估：
- `swift scripts/impact-detect.swift` 输出 L0/L1/L2/L3 影响面（基于 `git diff --name-only`）
- T2 测试（网络 API）仅在 `main` 分支运行，需要 `PSS_USERNAME` / `PSS_PASSWORD` secret

## 已知架构约束

- App 运行在 Sandbox 中（`App.entitlements`），网络、文件选择、Apple Events 已授权
- Keychain 存 API Key (`CredentialStore` + `SecureCredentialStore`)
- FileVault 关闭时会打印 `[Storage] FileVault is OFF` 警告
- 隐私过滤 (`PrivacyFilter`) 在发送到云端之前对请求做脱敏
- 内存 5 层架构：Working/Session/Case/LongTerm/Global，`MemoryConsolidator` 每 6h 运行
- `readOnlyTools` 声明在 `ToolDispatch.swift`，影响 readOnly 判定
- 文件撤销基于 `FileSnapshotStore` 文件系统快照（非 undo log）

## CodeGraph

项目已索引（206 文件 / 3595 edge）。优先从 `codegraph_context` / `codegraph_trace` / `codegraph_search` 入口而非 grep。`.cursor/rules/codegraph.mdc` 有完整使用指南。
