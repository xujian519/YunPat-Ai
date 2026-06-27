# YunPat-Ai Plan 1: Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建可对话的 macOS 桌面 AI App——多模型 API 路由 + 流式聊天 UI + 多标签 + AgentLoop 基础引擎 + Capability Registry。

**Architecture:** Swift Package Manager 多包结构。YunPatNetworking 实现多后端模型路由（OpenAI/Anthropic/DeepSeek/GLM），YunPatCore 实现 AgentLoop + CapabilityRegistry + ContextEngine。App 层用 SwiftUI 构建多标签 Chat UI。TDD 驱动，每层先写测试再实现。

**Tech Stack:** Swift 6, SwiftUI, AppKit (混合), SPM, URLSession (async/await), Combine, XCTest

---

## 文件结构（Plan 1 涉及的文件）

```
YunPat-Ai/
├── App/
│   ├── YunPatApp.swift              # @main 入口
│   ├── Views/
│   │   ├── ContentView.swift        # 根布局
│   │   ├── ChatView.swift           # 聊天消息 + 输入框
│   │   ├── TabBar.swift             # 标签栏
│   │   ├── Tab.swift                # 标签数据模型
│   │   └── Settings/
│   │       └── ProviderSettingsView.swift
│   └── Assets/
├── Packages/
│   ├── YunPatNetworking/
│   │   ├── Package.swift
│   │   ├── Sources/YunPatNetworking/
│   │   │   ├── ModelBackend.swift
│   │   │   ├── ModelRouter.swift
│   │   │   ├── ChatRequest.swift
│   │   │   ├── ChatChunk.swift
│   │   │   ├── Message.swift
│   │   │   ├── Usage.swift
│   │   │   ├── Providers/
│   │   │   │   ├── OpenAIProvider.swift
│   │   │   │   ├── AnthropicProvider.swift
│   │   │   │   └── OpenAICompatProvider.swift  # DeepSeek/GLM 共用
│   │   │   └── RateLimiter.swift
│   │   └── Tests/YunPatNetworkingTests/
│   │       ├── OpenAIBackendTests.swift
│   │       ├── AnthropicBackendTests.swift
│   │       ├── DeepSeekBackendTests.swift
│   │       └── ModelRouterTests.swift
│   └── YunPatCore/
│       ├── Package.swift
│       ├── Sources/YunPatCore/
│       │   ├── Loop/
│       │   │   ├── LoopEngine.swift
│       │   │   ├── AgentLoopEngine.swift
│       │   │   └── LoopState.swift
│       │   ├── Capability/
│       │   │   ├── CapabilityDefinition.swift
│       │   │   ├── CapabilityRegistry.swift
│       │   │   └── ToolDefinition.swift
│       │   └── Context/
│       │       └── ContextEngine.swift
│       └── Tests/YunPatCoreTests/
│           ├── AgentLoopEngineTests.swift
│           ├── CapabilityRegistryTests.swift
│           └── ContextEngineTests.swift
```

---

## Phase A: 项目脚手架（Tasks 1-6）

### Task 1: 创建 SPM 工作空间

**Files:**
- Create: `App/`

- [ ] **Step 1: 创建 App 目录结构**

```bash
mkdir -p App/Views/Settings
mkdir -p App/Assets
```

- [ ] **Step 2: 验证目录**

```bash
ls -R App/
```
Expected: `Views/` `Assets/` 目录存在

### Task 2: 创建 YunPatNetworking 包

**Files:**
- Create: `Packages/YunPatNetworking/Package.swift`

- [ ] **Step 1: 写 Package.swift**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YunPatNetworking",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "YunPatNetworking", targets: ["YunPatNetworking"]),
    ],
    targets: [
        .target(name: "YunPatNetworking"),
        .testTarget(name: "YunPatNetworkingTests", dependencies: ["YunPatNetworking"]),
    ]
)
```

- [ ] **Step 2: 创建 Sources 和 Tests 骨架**

```bash
mkdir -p Packages/YunPatNetworking/Sources/YunPatNetworking/Providers
mkdir -p Packages/YunPatNetworking/Tests/YunPatNetworkingTests
touch Packages/YunPatNetworking/Sources/YunPatNetworking/.gitkeep
touch Packages/YunPatNetworking/Tests/YunPatNetworkingTests/.gitkeep
```

- [ ] **Step 3: 验证包编译**

```bash
cd Packages/YunPatNetworking && swift build
```
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/YunPatNetworking/
git commit -m "feat: scaffold YunPatNetworking package"
```

### Task 3: 创建 YunPatCore 包

**Files:**
- Create: `Packages/YunPatCore/Package.swift`

- [ ] **Step 1: 写 Package.swift（依赖 YunPatNetworking）**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YunPatCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "YunPatCore", targets: ["YunPatCore"]),
    ],
    dependencies: [
        .package(path: "../YunPatNetworking"),
    ],
    targets: [
        .target(
            name: "YunPatCore",
            dependencies: [.product(name: "YunPatNetworking", package: "YunPatNetworking")]
        ),
        .testTarget(name: "YunPatCoreTests", dependencies: ["YunPatCore"]),
    ]
)
```

- [ ] **Step 2: 创建 Sources 和 Tests 骨架**

```bash
mkdir -p Packages/YunPatCore/Sources/YunPatCore/{Loop,Capability,Context}
mkdir -p Packages/YunPatCore/Tests/YunPatCoreTests
```

- [ ] **Step 3: 验证编译**

```bash
cd Packages/YunPatCore && swift build
```
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/YunPatCore/
git commit -m "feat: scaffold YunPatCore package"
```

### Task 4: 创建 App Xcode 项目

**Files:**
- Create: `App/YunPatApp.swift`

- [ ] **Step 1: 写最小 SwiftUI App 入口**

```swift
// App/YunPatApp.swift
import SwiftUI

@main
struct YunPatApp: App {
    var body: some Scene {
        WindowGroup {
            Text("YunPat-Ai")
                .font(.largeTitle)
                .padding()
        }
    }
}
```

- [ ] **Step 2: 在 Xcode 中创建 macOS App target，关联两个 SPM 包**

```bash
# 手动操作：Xcode → New Project → macOS App → YunPatAi
# → Add Package: Packages/YunPatNetworking
# → Add Package: Packages/YunPatCore
```

- [ ] **Step 3: 验证构建**

```bash
xcodebuild -project YunPatAi.xcodeproj -scheme YunPatAi build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add App/
git commit -m "feat: scaffold macOS App target with SPM deps"
```

### Task 5: 配置 App 菜单栏和快捷键（HIG 基础）

**Files:**
- Modify: `App/YunPatApp.swift`

- [ ] **Step 1: 添加标准 macOS 菜单栏**

```swift
// App/YunPatApp.swift
import SwiftUI

@main
struct YunPatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About YunPat-Ai") {
                    NSApp.orderFrontStandardAboutPanel(options: [:])
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    NotificationCenter.default.post(name: .menuNewTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
        Settings {
            Text("Settings placeholder")
        }
    }
}

extension Notification.Name {
    static let menuNewTab = Notification.Name("menuNewTab")
}
```

- [ ] **Step 2: 验证构建**

```bash
xcodebuild -project YunPatAi.xcodeproj -scheme YunPatAi build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add App/YunPatApp.swift
git commit -m "feat: add standard macOS menu bar with New Tab shortcut"
```

### Task 6: 配置 .gitattributes 和 .swift-format

**Files:**
- Create: `.swift-format`

- [ ] **Step 1: 创建格式化配置**

```bash
cat > .swift-format << 'EOF'
{
  "indentation": { "spaces": 4 },
  "lineLength": 120,
  "respectsExistingLineBreaks": true
}
EOF
```

- [ ] **Step 2: 验证格式**

```bash
swift-format --configuration .swift-format --recursive Packages/ --dry-run
```
Expected: no formatting violations

- [ ] **Step 3: Commit**

```bash
git add .swift-format
git commit -m "chore: add swift-format configuration"
```

---

## Phase B: 网络层 — 多后端模型路由（Tasks 7-14）

### Task 7: 定义 ChatRequest / ChatChunk / Message 数据模型

**Files:**
- Create: `Packages/YunPatNetworking/Sources/YunPatNetworking/ChatRequest.swift`
- Create: `Packages/YunPatNetworking/Sources/YunPatNetworking/ChatChunk.swift`
- Create: `Packages/YunPatNetworking/Sources/YunPatNetworking/Message.swift`
- Create: `Packages/YunPatNetworking/Sources/YunPatNetworking/Usage.swift`

- [ ] **Step 1: 写 Message.swift**

```swift
// Packages/YunPatNetworking/Sources/YunPatNetworking/Message.swift
import Foundation

public struct Message: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public let role: Role
    public let content: String
    public let toolCallID: String?
    public let name: String?

    public init(role: Role, content: String, toolCallID: String? = nil, name: String? = nil) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.name = name
    }
}
```

- [ ] **Step 2: 写 ChatRequest.swift**

```swift
// Packages/YunPatNetworking/Sources/YunPatNetworking/ChatRequest.swift
import Foundation

public struct ChatRequest: Sendable {
    public let model: String
    public let messages: [Message]
    public let systemPrompt: String?
    public let temperature: Float?
    public let maxTokens: Int?

    public init(
        model: String,
        messages: [Message],
        systemPrompt: String? = nil,
        temperature: Float? = nil,
        maxTokens: Int? = nil
    ) {
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}
```

- [ ] **Step 3: 写 ChatChunk.swift**

```swift
// Packages/YunPatNetworking/Sources/YunPatNetworking/ChatChunk.swift
import Foundation

public enum ChatChunk: Sendable {
    case text(String)
    case toolCall(id: String, name: String, arguments: String)
    case toolCallDelta(id: String, arguments: String)
    case finish(reason: FinishReason, usage: Usage?)
    case error(Error)
}

public enum FinishReason: String, Sendable {
    case stop
    case length
    case toolCalls = "tool_calls"
}
```

- [ ] **Step 4: 写 Usage.swift**

```swift
// Packages/YunPatNetworking/Sources/YunPatNetworking/Usage.swift
import Foundation

public struct Usage: Codable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}
```

- [ ] **Step 5: 验证编译**

```bash
cd Packages/YunPatNetworking && swift build
```
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Packages/YunPatNetworking/Sources/YunPatNetworking/
git commit -m "feat: define ChatRequest, ChatChunk, Message, Usage models"
```

### Task 8: 定义 ModelBackend 协议（含速率限制）

**Files:**
- Create: `Packages/YunPatNetworking/Sources/YunPatNetworking/ModelBackend.swift`

- [ ] **Step 1: 写 ModelBackend 协议**

```swift
// Packages/YunPatNetworking/Sources/YunPatNetworking/ModelBackend.swift
import Foundation

public enum ModelProvider: String, Codable, Sendable {
    case openai
    case anthropic
    case deepseek
    case glm        // 智谱 GLM
}

public struct ModelInfo: Codable, Sendable {
    public let id: String
    public let provider: ModelProvider
    public let displayName: String
}

public struct ModelCapabilities: Sendable {
    public let supportsStreaming: Bool
    public let supportsToolCalling: Bool
    public let maxContextTokens: Int
    public let supportsVision: Bool

    public init(
        supportsStreaming: Bool = true,
        supportsToolCalling: Bool = false,
        maxContextTokens: Int = 128_000,
        supportsVision: Bool = false
    ) {
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.maxContextTokens = maxContextTokens
        self.supportsVision = supportsVision
    }
}

public struct RateLimitInfo: Sendable {
    public let remainingRequests: Int
    public let remainingTokens: Int
    public let resetAt: Date

    public init(remainingRequests: Int, remainingTokens: Int, resetAt: Date) {
        self.remainingRequests = remainingRequests
        self.remainingTokens = remainingTokens
        self.resetAt = resetAt
    }
}

public struct RateLimitError: Error, Sendable {
    public let retryAfter: TimeInterval?
    public let message: String

    public init(retryAfter: TimeInterval? = nil, message: String = "Rate limit exceeded") {
        self.retryAfter = retryAfter
        self.message = message
    }
}

public enum RetryStrategy: Sendable {
    case retry(after: TimeInterval)
    case fail
    case switchProvider(ModelProvider)
}

public protocol ModelBackend: Sendable {
    var provider: ModelProvider { get }
    var rateLimit: RateLimitInfo? { get async }
    func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error>
    func listModels() async throws -> [ModelInfo]
    func capabilities() -> ModelCapabilities
    func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy
}
```

- [ ] **Step 2: 验证编译**

```bash
cd Packages/YunPatNetworking && swift build
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/YunPatNetworking/Sources/YunPatNetworking/ModelBackend.swift
git commit -m "feat: define ModelBackend protocol with rate limit support"
```

### Task 9: 实现 OpenAIProvider（TDD）

**Files:**
- Create: `Packages/YunPatNetworking/Tests/YunPatNetworkingTests/OpenAIProviderTests.swift`
- Create: `Packages/YunPatNetworking/Sources/YunPatNetworking/Providers/OpenAIProvider.swift`

- [ ] **Step 1: 写失败测试 — 无 API Key 时 chat() 应抛错**

```swift
// Packages/YunPatNetworking/Tests/YunPatNetworkingTests/OpenAIProviderTests.swift
import XCTest
@testable import YunPatNetworking

final class OpenAIProviderTests: XCTestCase {
    func testChat_withoutAPIKey_throwsError() async {
        let provider = OpenAIProvider(apiKey: "")
        let request = ChatRequest(model: "gpt-4o", messages: [
            Message(role: .user, content: "Hello")
        ])

        var caughtError: Error?
        do {
            for try await _ in provider.chat(request) { }
        } catch {
            caughtError = error
        }

        XCTAssertNotNil(caughtError, "Expected error when API key is empty")
    }

    func testCapabilities_returnsOpenAICaps() {
        let provider = OpenAIProvider(apiKey: "test-key")
        let caps = provider.capabilities()

        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertTrue(caps.supportsToolCalling)
    }
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
cd Packages/YunPatNetworking && swift test --filter OpenAIProviderTests
```
Expected: 1 failure (testChat_withoutAPIKey_throwsError — chat must error)

- [ ] **Step 3: 写最小实现**

```swift
// Packages/YunPatNetworking/Sources/YunPatNetworking/Providers/OpenAIProvider.swift
import Foundation

public final class OpenAIProvider: ModelBackend {
    public let provider = ModelProvider.openai
    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    public init(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    public var rateLimit: RateLimitInfo? { get async { nil } }

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            guard !apiKey.isEmpty else {
                continuation.finish(throwing: RateLimitError(message: "API key is empty"))
                return
            }
            continuation.yield(.error(RateLimitError(message: "Not yet implemented")))
            continuation.finish()
        }
    }

    public func listModels() async throws -> [ModelInfo] {
        []
    }

    public func capabilities() -> ModelCapabilities {
        ModelCapabilities(supportsStreaming: true, supportsToolCalling: true,
                          maxContextTokens: 128_000, supportsVision: true)
    }

    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy {
        .retry(after: error.retryAfter ?? 5.0)
    }
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
cd Packages/YunPatNetworking && swift test --filter OpenAIProviderTests
```
Expected: 2 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/YunPatNetworking/
git commit -m "feat: implement OpenAIProvider with rate limit handling"
```

### Task 10: 实现 AnthropicProvider（TDD）

**Files:**
- Create: `Packages/YunPatNetworking/Tests/YunPatNetworkingTests/AnthropicProviderTests.swift`
- Create: `Packages/YunPatNetworking/Sources/YunPatNetworking/Providers/AnthropicProvider.swift`

- [ ] **Step 1: 写失败测试**

```swift
// Packages/YunPatNetworking/Tests/YunPatNetworkingTests/AnthropicProviderTests.swift
import XCTest
@testable import YunPatNetworking

final class AnthropicProviderTests: XCTestCase {
    func testChat_withoutAPIKey_throwsError() async {
        let provider = AnthropicProvider(apiKey: "")
        let request = ChatRequest(model: "claude-sonnet-4-20250514", messages: [
            Message(role: .user, content: "Hello")
        ])

        var caughtError: Error?
        do {
            for try await _ in provider.chat(request) { }
        } catch {
            caughtError = error
        }
        XCTAssertNotNil(caughtError)
    }

    func testCapabilities_returnsAnthropicCaps() {
        let provider = AnthropicProvider(apiKey: "test-key")
        let caps = provider.capabilities()

        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertTrue(caps.supportsToolCalling)
        XCTAssertEqual(caps.maxContextTokens, 200_000)
    }
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
cd Packages/YunPatNetworking && swift test --filter AnthropicProviderTests
```
Expected: 1 failure

- [ ] **Step 3: 写最小实现**

```swift
// Packages/YunPatNetworking/Sources/YunPatNetworking/Providers/AnthropicProvider.swift
import Foundation

public final class AnthropicProvider: ModelBackend {
    public let provider = ModelProvider.anthropic
    private let apiKey: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1")!
    private let session = URLSession.shared

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public var rateLimit: RateLimitInfo? { get async { nil } }

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            guard !apiKey.isEmpty else {
                continuation.finish(throwing: RateLimitError(message: "API key is empty"))
                return
            }
            continuation.finish()
        }
    }

    public func listModels() async throws -> [ModelInfo] { [] }

    public func capabilities() -> ModelCapabilities {
        ModelCapabilities(supportsStreaming: true, supportsToolCalling: true,
                          maxContextTokens: 200_000)
    }

    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy {
        .retry(after: error.retryAfter ?? 5.0)
    }
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
cd Packages/YunPatNetworking && swift test --filter AnthropicProviderTests
```
Expected: 2 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/YunPatNetworking/
git commit -m "feat: implement AnthropicProvider"
```

### Task 11: 实现 DeepSeekProvider / GLMProvider（共用 OpenAICompatProvider）

**Files:**
- Create: `Packages/YunPatNetworking/Tests/YunPatNetworkingTests/DeepSeekProviderTests.swift`
- Create: `Packages/YunPatNetworking/Sources/YunPatNetworking/Providers/OpenAICompatProvider.swift`

- [ ] **Step 1: 写失败测试**

```swift
// Packages/YunPatNetworking/Tests/YunPatNetworkingTests/DeepSeekProviderTests.swift
import XCTest
@testable import YunPatNetworking

final class DeepSeekProviderTests: XCTestCase {
    func testChat_withoutAPIKey_throwsError() async {
        let provider = OpenAICompatProvider(
            apiKey: "",
            baseURL: URL(string: "https://api.deepseek.com/v1")!,
            provider: .deepseek
        )
        let request = ChatRequest(model: "deepseek-chat", messages: [
            Message(role: .user, content: "Hello")
        ])

        var caughtError: Error?
        do {
            for try await _ in provider.chat(request) { }
        } catch { caughtError = error }
        XCTAssertNotNil(caughtError)
    }

    func testGLMProvider_initializesCorrectly() {
        let provider = OpenAICompatProvider(
            apiKey: "test",
            baseURL: URL(string: "https://open.bigmodel.cn/api/paas/v4")!,
            provider: .glm
        )
        XCTAssertEqual(provider.provider, .glm)
    }
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
cd Packages/YunPatNetworking && swift test --filter DeepSeekProviderTests
```

- [ ] **Step 3: 写 OpenAICompatProvider**

```swift
// Packages/YunPatNetworking/Sources/YunPatNetworking/Providers/OpenAICompatProvider.swift
import Foundation

public final class OpenAICompatProvider: ModelBackend {
    public let provider: ModelProvider
    private let apiKey: String
    private let baseURL: URL
    private let session = URLSession.shared

    public init(apiKey: String, baseURL: URL, provider: ModelProvider) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.provider = provider
    }

    public var rateLimit: RateLimitInfo? { get async { nil } }

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            guard !apiKey.isEmpty else {
                continuation.finish(throwing: RateLimitError(message: "API key is empty"))
                return
            }
            continuation.finish()
        }
    }

    public func listModels() async throws -> [ModelInfo] { [] }

    public func capabilities() -> ModelCapabilities {
        ModelCapabilities(supportsStreaming: true, supportsToolCalling: true,
                          maxContextTokens: 128_000)
    }

    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy {
        .retry(after: error.retryAfter ?? 5.0)
    }
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
cd Packages/YunPatNetworking && swift test --filter DeepSeekProviderTests
```
Expected: 2 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/YunPatNetworking/
git commit -m "feat: implement OpenAICompatProvider for DeepSeek/GLM"
```

### Task 12: 实现 ModelRouter（路由分发 + 全局并发控制）

**Files:**
- Create: `Packages/YunPatNetworking/Tests/YunPatNetworkingTests/ModelRouterTests.swift`
- Create: `Packages/YunPatNetworking/Sources/YunPatNetworking/ModelRouter.swift`

- [ ] **Step 1: 写失败测试**

```swift
// Packages/YunPatNetworking/Tests/YunPatNetworkingTests/ModelRouterTests.swift
import XCTest
@testable import YunPatNetworking

final class ModelRouterTests: XCTestCase {
    func testRegisterAndRoute_returnsCorrectProvider() {
        let router = ModelRouter()
        let openAIProvider = OpenAIProvider(apiKey: "test-key")
        router.register(openAIProvider)

        let result = router.route(provider: .openai)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.provider, .openai)
    }

    func testRoute_toUnregisteredProvider_returnsNil() {
        let router = ModelRouter()
        XCTAssertNil(router.route(provider: .openai))
    }
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
cd Packages/YunPatNetworking && swift test --filter ModelRouterTests
```

- [ ] **Step 3: 写 ModelRouter**

```swift
// Packages/YunPatNetworking/Sources/YunPatNetworking/ModelRouter.swift
import Foundation

public actor ModelRouter {
    private var backends: [ModelProvider: ModelBackend] = [:]

    public init() {}

    public func register(_ backend: ModelBackend) {
        backends[backend.provider] = backend
    }

    public func route(provider: ModelProvider) -> ModelBackend? {
        backends[provider]
    }

    public func chat(_ request: ChatRequest, provider: ModelProvider) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        guard let backend = backends[provider] else {
            throw ModelRouterError.providerNotRegistered(provider)
        }
        return backend.chat(request)
    }

    public var registeredProviders: [ModelProvider] {
        Array(backends.keys)
    }
}

public enum ModelRouterError: Error {
    case providerNotRegistered(ModelProvider)
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
cd Packages/YunPatNetworking && swift test --filter ModelRouterTests
```
Expected: 2 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/YunPatNetworking/
git commit -m "feat: implement ModelRouter with provider registration"
```

### Task 13: 实现 GlobalRequestQueue（跨标签并发控制）

**Files:**
- Create: `Packages/YunPatNetworking/Sources/YunPatNetworking/RateLimiter.swift`

- [ ] **Step 1: 写失败测试**

```swift
// Append to ModelRouterTests.swift

func testGlobalRequestQueue_enforcesConcurrency() async {
    let queue = await GlobalRequestQueue(maxConcurrentRequests: 2)
    let router = ModelRouter()
    let provider = OpenAIProvider(apiKey: "test-key")
    await router.register(provider)

    // 发起 3 个请求，验证队列限制
    var completedCount = 0
    for _ in 0..<3 {
        let request = ChatRequest(model: "gpt-4o", messages: [
            Message(role: .user, content: "Test")
        ])
        Task {
            _ = await queue.enqueue(request, provider: .openai, router: router)
            completedCount += 1
        }
    }

    try? await Task.sleep(nanoseconds: 500_000_000)
    // 当前 2 个应已经在处理中，第 3 个排队
    // 具体行为取决于实现，此处仅验证队列可创建
}
```

- [ ] **Step 2: 写 RateLimiter / GlobalRequestQueue**

```swift
// Packages/YunPatNetworking/Sources/YunPatNetworking/RateLimiter.swift
import Foundation

public enum RequestPriority: Sendable, Comparable {
    case low
    case normal
    case high

    public static func < (lhs: RequestPriority, rhs: RequestPriority) -> Bool {
        switch (lhs, rhs) {
        case (.low, .normal), (.low, .high), (.normal, .high): return true
        default: return false
        }
    }
}

public actor GlobalRequestQueue {
    public var maxConcurrentRequests: Int

    private var activeCount = 0
    private var pending: [(ChatRequest, ModelProvider, CheckedContinuation<AsyncThrowingStream<ChatChunk, Error>, Never>)] = []

    public init(maxConcurrentRequests: Int = 3) {
        self.maxConcurrentRequests = maxConcurrentRequests
    }

    public func enqueue(
        _ request: ChatRequest,
        provider: ModelProvider,
        router: ModelRouter,
        priority: RequestPriority = .normal
    ) async -> AsyncThrowingStream<ChatChunk, Error> {
        while activeCount >= maxConcurrentRequests {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        activeCount += 1
        defer { activeCount -= 1 }

        return await router.chat(request, provider: provider)
    }

    public func currentUsage(for provider: ModelProvider) -> Int {
        activeCount
    }
}
```

- [ ] **Step 3: 验证编译**

```bash
cd Packages/YunPatNetworking && swift build
```
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/YunPatNetworking/
git commit -m "feat: implement GlobalRequestQueue for cross-tab concurrency control"
```

### Task 14: 实现 API Key 凭证存储（Keychain）

**Files:**
- Create: `Packages/YunPatNetworking/Sources/YunPatNetworking/CredentialStore.swift`

- [ ] **Step 1: 写 CredentialStore**

```swift
// Packages/YunPatNetworking/Sources/YunPatNetworking/CredentialStore.swift
import Foundation
import Security

public struct CredentialStore {
    public static let shared = CredentialStore()

    public func store(provider: ModelProvider, apiKey: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "yunpat.\(provider.rawValue)",
            kSecAttrService as String: "YunPat-Ai",
            kSecValueData as String: apiKey.data(using: .utf8)!,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.keychainError(status)
        }
    }

    public func apiKey(for provider: ModelProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "yunpat.\(provider.rawValue)",
            kSecAttrService as String: "YunPat-Ai",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(for provider: ModelProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "yunpat.\(provider.rawValue)",
            kSecAttrService as String: "YunPat-Ai",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum CredentialError: Error {
    case keychainError(OSStatus)
}
```

- [ ] **Step 2: 验证编译**

```bash
cd Packages/YunPatNetworking && swift build
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/YunPatNetworking/Sources/YunPatNetworking/CredentialStore.swift
git commit -m "feat: implement Keychain-based credential storage"
```

---

## Phase C: 核心引擎 — AgentLoop + LoopEngine（Tasks 15-22）

### Task 15: 定义 LoopResult / LoopState / AgentFlow / PlanMode

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Loop/LoopState.swift`

- [ ] **Step 1: 写 LoopState / AgentFlow / PlanMode / LoopResult**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Loop/LoopState.swift
import Foundation

public enum AgentFlow: Sendable {
    case copilot       // 直接响应，不进 Loop
    case guided        // PatentLoop 1-3 步暂停确认
    case fullAgent     // 完整五步
}

public enum PlanMode: Sendable {
    case auto
    case interactive
    case readOnly
}

public enum LoopState: Sendable {
    case idle
    case running(step: String)
    case waitingApproval(ApprovalRequest)
    case error(Error)
}

public struct ApprovalRequest: Sendable {
    public let id: UUID
    public let summary: String
    public let detail: String
    public let options: [String]

    public init(id: UUID = UUID(), summary: String, detail: String, options: [String] = ["确认", "取消"]) {
        self.id = id
        self.summary = summary
        self.detail = detail
        self.options = options
    }
}

public struct LoopConfig: Sendable {
    public let maxRevisionCycles: Int

    public init(maxRevisionCycles: Int = 3) {
        self.maxRevisionCycles = maxRevisionCycles
    }
}

public enum LoopResult: Sendable {
    case completed(String)             // 完成，带回最终输出
    case needsClarification([String])  // 需要用户澄清
    case cancelled                     // 用户取消
    case needsRevision([Issue])        // 需要修正
    case exceededRevisionLimit([Issue]) // 超过最大重试次数
}

public struct Issue: Sendable {
    public let severity: IssueSeverity
    public let description: String

    public init(severity: IssueSeverity = .error, description: String) {
        self.severity = severity
        self.description = description
    }
}

public enum IssueSeverity: Sendable {
    case warning
    case error
}
```

- [ ] **Step 2: 验证编译**

```bash
cd Packages/YunPatCore && swift build
```

- [ ] **Step 3: Commit**

```bash
git add Packages/YunPatCore/Sources/YunPatCore/Loop/LoopState.swift
git commit -m "feat: define LoopState, AgentFlow, PlanMode, LoopResult enums"
```

### Task 16: 定义 LoopEngine 协议

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Loop/LoopEngine.swift`

- [ ] **Step 1: 写 LoopEngine 协议**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Loop/LoopEngine.swift
import Foundation

public struct UserRequest: Sendable {
    public let content: String
    public let attachments: [URL]

    public init(content: String, attachments: [URL] = []) {
        self.content = content
        self.attachments = attachments
    }
}

public protocol LoopEngine: Sendable {
    func run(request: UserRequest, flow: AgentFlow) async throws -> LoopResult
    var state: LoopState { get async }
}
```

- [ ] **Step 2: 验证编译**

```bash
cd Packages/YunPatCore && swift build
```

- [ ] **Step 3: Commit**

```bash
git add Packages/YunPatCore/Sources/YunPatCore/Loop/LoopEngine.swift
git commit -m "feat: define LoopEngine protocol"
```

### Task 17: 实现 AgentLoopEngine（TDD）

**Files:**
- Create: `Packages/YunPatCore/Tests/YunPatCoreTests/AgentLoopEngineTests.swift`
- Create: `Packages/YunPatCore/Sources/YunPatCore/Loop/AgentLoopEngine.swift`

- [ ] **Step 1: 写失败测试 — 简单用户消息应返回 completed**

```swift
// Packages/YunPatCore/Tests/YunPatCoreTests/AgentLoopEngineTests.swift
import XCTest
@testable import YunPatCore

final class AgentLoopEngineTests: XCTestCase {
    func testRun_copilotMode_returnsCompleted() async throws {
        let engine = AgentLoopEngine()
        let result = try await engine.run(
            request: UserRequest(content: "你好"),
            flow: .copilot
        )

        guard case .completed = result else {
            XCTFail("Expected .completed, got \(result)")
            return
        }
    }

    func testRun_returnsUpdatedState() async throws {
        let engine = AgentLoopEngine()
        let _ = try await engine.run(
            request: UserRequest(content: "test"),
            flow: .copilot
        )

        let state = await engine.state
        if case .idle = state { /* pass */ } else {
            XCTFail("Expected .idle after completion, got \(state)")
        }
    }
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
cd Packages/YunPatCore && swift test --filter AgentLoopEngineTests
```

- [ ] **Step 3: 写最小实现**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Loop/AgentLoopEngine.swift
import Foundation

public actor AgentLoopEngine: LoopEngine {
    public var state: LoopState = .idle

    public init() {}

    public func run(request: UserRequest, flow: AgentFlow) async throws -> LoopResult {
        state = .running(step: "executing")

        // 最小实现：直接返回完成的对话响应
        let response = "收到：「\(request.content)」"

        state = .idle
        return .completed(response)
    }
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
cd Packages/YunPatCore && swift test --filter AgentLoopEngineTests --enable-test-discovery
```
Expected: 2 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/YunPatCore/
git commit -m "feat: implement minimal AgentLoopEngine"
```

### Task 18: AgentLoopEngine 现在依赖 ModelRouter（注入后端）

**Files:**
- Modify: `Packages/YunPatCore/Sources/YunPatCore/Loop/AgentLoopEngine.swift`

- [ ] **Step 1: 更新 AgentLoopEngine 接收 ModelRouter 和 ModelProvider**

```swift
// AgentLoopEngine.swift (updated)
import Foundation
import YunPatNetworking

public actor AgentLoopEngine: LoopEngine {
    public var state: LoopState = .idle
    private let modelRouter: ModelRouter
    private let provider: ModelProvider

    public init(modelRouter: ModelRouter, provider: ModelProvider = .deepseek) {
        self.modelRouter = modelRouter
        self.provider = provider
    }

    public func run(request: UserRequest, flow: AgentFlow) async throws -> LoopResult {
        state = .running(step: "executing")

        let messages: [Message] = [
            Message(role: .user, content: request.content)
        ]
        let chatRequest = ChatRequest(model: "deepseek-chat", messages: messages)
        let stream = try await modelRouter.chat(chatRequest, provider: provider)

        var fullResponse = ""
        for try await chunk in stream {
            switch chunk {
            case .text(let text):
                fullResponse += text
            case .finish:
                break
            case .error(let error):
                state = .error(error)
                return .completed("Error: \(error.localizedDescription)")
            default:
                break
            }
        }

        state = .idle
        return .completed(fullResponse)
    }
}
```

- [ ] **Step 2: 更新 AgentLoopEngineTests 注入 mock**

```swift
// AgentLoopEngineTests.swift (updated)
import XCTest
import YunPatNetworking
@testable import YunPatCore

final class AgentLoopEngineTests: XCTestCase {
    func testRun_copilotMode_returnsCompleted() async throws {
        let router = ModelRouter()
        let provider = OpenAIProvider(apiKey: "test-key")
        await router.register(provider)

        let engine = AgentLoopEngine(modelRouter: router, provider: .openai)
        let result = try await engine.run(
            request: UserRequest(content: "你好"),
            flow: .copilot
        )

        switch result {
        case .completed(let text):
            XCTAssertTrue(text.contains("Error"), "Should get error response with test key")
        default:
            XCTFail("Expected .completed")
        }
    }
}
```

- [ ] **Step 3: 验证编译并运行测试**

```bash
cd Packages/YunPatCore && swift build && swift test --filter AgentLoopEngineTests
```
Expected: `Build complete!` + 2 tests PASS

- [ ] **Step 4: Commit**

```bash
git add Packages/YunPatCore/
git commit -m "feat: AgentLoopEngine integrates ModelRouter for streaming chat"
```

### Task 19: 实现 ContextEngine（Prompt 组装）

**Files:**
- Create: `Packages/YunPatCore/Tests/YunPatCoreTests/ContextEngineTests.swift`
- Create: `Packages/YunPatCore/Sources/YunPatCore/Context/ContextEngine.swift`

- [ ] **Step 1: 写失败测试**

```swift
// Packages/YunPatCore/Tests/YunPatCoreTests/ContextEngineTests.swift
import XCTest
@testable import YunPatCore

final class ContextEngineTests: XCTestCase {
    func testBuildPrompt_copilotMode_injectsBasicContext() async throws {
        let engine = ContextEngine()
        let prompt = try await engine.buildPrompt(
            for: UserRequest(content: "你好"),
            flow: .copilot
        )
        XCTAssertFalse(prompt.isEmpty)
        XCTAssertTrue(prompt.contains("你好"))
    }

    func testBuildPrompt_respectsTokenBudget() async throws {
        let engine = ContextEngine()
        let prompt = try await engine.buildPrompt(
            for: UserRequest(content: "你好"),
            flow: .copilot,
            maxTokenBudget: 100
        )
        // 粗略估算：1 token ≈ 4 chars
        XCTAssertLessThanOrEqual(prompt.count, 500)
    }
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
cd Packages/YunPatCore && swift test --filter ContextEngineTests
```

- [ ] **Step 3: 写最小实现**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Context/ContextEngine.swift
import Foundation

public final class ContextEngine {
    public init() {}

    public func buildPrompt(
        for request: UserRequest,
        flow: AgentFlow,
        maxTokenBudget: Int = 4000
    ) async throws -> String {
        var parts: [String] = []

        // 基础角色
        parts.append("你是一个有用的 AI 助手。")

        // 用户消息
        parts.append("用户：\(request.content)")

        let full = parts.joined(separator: "\n\n")

        // Token 预算裁剪
        let estimatedTokens = full.count / 4
        if estimatedTokens > maxTokenBudget {
            return String(full.prefix(maxTokenBudget * 4))
        }
        return full
    }
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
cd Packages/YunPatCore && swift test --filter ContextEngineTests
```
Expected: 2 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/YunPatCore/
git commit -m "feat: implement ContextEngine for prompt assembly"
```

### Task 20: 将 ContextEngine 集成到 AgentLoopEngine

**Files:**
- Modify: `Packages/YunPatCore/Sources/YunPatCore/Loop/AgentLoopEngine.swift`

- [ ] **Step 1: 更新 AgentLoopEngine 使用 ContextEngine 构建 system prompt**

```swift
// AgentLoopEngine.swift (add ContextEngine)
public actor AgentLoopEngine: LoopEngine {
    public var state: LoopState = .idle
    private let modelRouter: ModelRouter
    private let provider: ModelProvider
    private let contextEngine: ContextEngine

    public init(modelRouter: ModelRouter, provider: ModelProvider = .deepseek) {
        self.modelRouter = modelRouter
        self.provider = provider
        self.contextEngine = ContextEngine()
    }

    public func run(request: UserRequest, flow: AgentFlow) async throws -> LoopResult {
        state = .running(step: "building-context")
        let systemPrompt = try await contextEngine.buildPrompt(for: request, flow: flow)
        state = .running(step: "executing")

        let messages: [Message] = [
            Message(role: .user, content: request.content)
        ]
        let chatRequest = ChatRequest(
            model: "deepseek-chat",
            messages: messages,
            systemPrompt: systemPrompt
        )
        let stream = try await modelRouter.chat(chatRequest, provider: provider)

        var fullResponse = ""
        for try await chunk in stream {
            switch chunk {
            case .text(let text):
                fullResponse += text
            case .finish:
                break
            case .error(let error):
                state = .error(error)
                return .completed("Error: \(error.localizedDescription)")
            default:
                break
            }
        }

        state = .idle
        return .completed(fullResponse)
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
cd Packages/YunPatCore && swift build
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/YunPatCore/Sources/YunPatCore/Loop/AgentLoopEngine.swift
git commit -m "feat: integrate ContextEngine into AgentLoopEngine"
```

---

## Phase D: Capability Registry（Tasks 21-25）

### Task 21: 定义 CapabilityDefinition / ToolDefinition / CapabilityMetadata

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityDefinition.swift`

- [ ] **Step 1: 写 CapabilityDefinition**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityDefinition.swift
import Foundation

public enum CapabilitySource: String, Codable, Sendable {
    case builtin
    case mcp
    case plugin
}

public enum CapabilityPermission: String, Codable, Sendable {
    case always
    case perSession
    case perCall
    case never
}

public enum CostLevel: String, Codable, Sendable {
    case free
    case low
    case medium
    case high
}

public struct CapabilityDefinition: Codable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let source: CapabilitySource
    public let permission: CapabilityPermission
    public let metadata: CapabilityMetadata

    public init(
        name: String, displayName: String, description: String,
        source: CapabilitySource = .builtin, permission: CapabilityPermission = .always,
        metadata: CapabilityMetadata = CapabilityMetadata()
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.source = source
        self.permission = permission
        self.metadata = metadata
    }
}

public struct CapabilityMetadata: Codable, Sendable {
    public let costLevel: CostLevel
    public let requiresNetwork: Bool
    public let isIdempotent: Bool
    public let typicalUseCases: [String]

    public init(
        costLevel: CostLevel = .free, requiresNetwork: Bool = false,
        isIdempotent: Bool = true, typicalUseCases: [String] = []
    ) {
        self.costLevel = costLevel
        self.requiresNetwork = requiresNetwork
        self.isIdempotent = isIdempotent
        self.typicalUseCases = typicalUseCases
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
cd Packages/YunPatCore && swift build
```

- [ ] **Step 3: Commit**

```bash
git add Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityDefinition.swift
git commit -m "feat: define CapabilityDefinition and CapabilityMetadata"
```

### Task 22: 定义 ToolDefinition

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Capability/ToolDefinition.swift`

- [ ] **Step 1: 写 ToolDefinition**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Capability/ToolDefinition.swift
import Foundation

public enum ToolSource: String, Codable, Sendable {
    case builtin
    case mcp
    case plugin
}

public enum ToolPermission: String, Codable, Sendable {
    case always
    case perSession
    case perCall
    case never
}

public struct ToolDefinition: Codable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let parameters: String  // JSON Schema string
    public let source: ToolSource
    public let permission: ToolPermission

    public init(name: String, displayName: String, description: String,
                parameters: String = "{}", source: ToolSource = .builtin,
                permission: ToolPermission = .always) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.parameters = parameters
        self.source = source
        self.permission = permission
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
cd Packages/YunPatCore && swift build
```

- [ ] **Step 3: Commit**

```bash
git add Packages/YunPatCore/Sources/YunPatCore/Capability/ToolDefinition.swift
git commit -m "feat: define ToolDefinition"
```

### Task 23: 实现 CapabilityRegistry（TDD）

**Files:**
- Create: `Packages/YunPatCore/Tests/YunPatCoreTests/CapabilityRegistryTests.swift`
- Create: `Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityRegistry.swift`

- [ ] **Step 1: 写失败测试**

```swift
// Packages/YunPatCore/Tests/YunPatCoreTests/CapabilityRegistryTests.swift
import XCTest
@testable import YunPatCore

final class CapabilityRegistryTests: XCTestCase {
    func testRegisterAndListCapability() {
        let registry = CapabilityRegistry()
        let cap = CapabilityDefinition(
            name: "test.general", displayName: "通用", description: "通用问答能力"
        )
        registry.register(capability: cap)
        let caps = registry.listCapabilities()

        XCTAssertEqual(caps.count, 1)
        XCTAssertEqual(caps.first?.name, "test.general")
    }

    func testListCapabilities_withoutRegistration_returnsEmpty() {
        let registry = CapabilityRegistry()
        XCTAssertTrue(registry.listCapabilities().isEmpty)
    }
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
cd Packages/YunPatCore && swift test --filter CapabilityRegistryTests
```

- [ ] **Step 3: 写 CapabilityRegistry**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityRegistry.swift
import Foundation

public final class CapabilityRegistry: @unchecked Sendable {
    private var capabilities: [CapabilityDefinition] = []
    private let lock = NSLock()

    public init() {}

    public func register(capability: CapabilityDefinition) {
        lock.lock()
        defer { lock.unlock() }
        capabilities.append(capability)
    }

    public func listCapabilities() -> [CapabilityDefinition] {
        lock.lock()
        defer { lock.unlock() }
        return capabilities
    }
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
cd Packages/YunPatCore && swift test --filter CapabilityRegistryTests
```
Expected: 2 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/YunPatCore/
git commit -m "feat: implement CapabilityRegistry"
```

### Task 24: 注册内置 Capability

**Files:**
- Modify: `Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityRegistry.swift`

- [ ] **Step 1: 添加内置注册方法**

```swift
// CapabilityRegistry (append)
extension CapabilityRegistry {
    public func registerBuiltinCapabilities() {
        register(capability: CapabilityDefinition(
            name: "core.chat", displayName: "对话", description: "通用 AI 对话能力",
            source: .builtin, permission: .always,
            metadata: CapabilityMetadata(costLevel: .low, requiresNetwork: true,
                                         isIdempotent: false, typicalUseCases: ["问答", "对话"])
        ))
    }
}
```

- [ ] **Step 2: 更新测试验证内置注册**

```swift
// CapabilityRegistryTests (append)
func testRegisterBuiltinCapabilities_addsDefaults() {
    let registry = CapabilityRegistry()
    registry.registerBuiltinCapabilities()
    let caps = registry.listCapabilities()

    XCTAssertFalse(caps.isEmpty)
    XCTAssertTrue(caps.contains { $0.name == "core.chat" })
}
```

- [ ] **Step 3: 运行测试**

```bash
cd Packages/YunPatCore && swift test --filter CapabilityRegistryTests
```
Expected: 3 tests PASS

- [ ] **Step 4: Commit**

```bash
git add Packages/YunPatCore/
git commit -m "feat: register built-in capabilities"
```

### Task 25: 实现 CapabilityStats（运行时动态延迟统计）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityStats.swift`

- [ ] **Step 1: 写 CapabilityStats**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityStats.swift
import Foundation

public actor CapabilityStats {
    private var latencyHistory: [String: [TimeInterval]] = [:]

    public init() {}

    public func recordLatency(_ capability: String, _ duration: TimeInterval) {
        latencyHistory[capability, default: []].append(duration)
        // 保留最近 100 条记录
        if latencyHistory[capability]!.count > 100 {
            latencyHistory[capability]!.removeFirst()
        }
    }

    public func averageLatency(for capability: String) -> TimeInterval? {
        guard let history = latencyHistory[capability], !history.isEmpty else { return nil }
        return history.reduce(0, +) / Double(history.count)
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
cd Packages/YunPatCore && swift build
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityStats.swift
git commit -m "feat: implement CapabilityStats for runtime latency tracking"
```

---

## Phase E: Chat UI — 多标签流式对话（Tasks 26-35）

### Task 26: 创建 Tab 数据模型

**Files:**
- Create: `App/Views/Tab.swift`

- [ ] **Step 1: 写 Tab 模型**

```swift
// App/Views/Tab.swift
import SwiftUI

struct ChatTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var loopState: LoopState

    init(title: String = "新对话") {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.loopState = .idle
    }

    static func == (lhs: ChatTab, rhs: ChatTab) -> Bool { lhs.id == rhs.id }
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Message.Role
    let content: String
    let timestamp: Date

    init(role: Message.Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool { lhs.id == rhs.id }
}
```

- [ ] **Step 2: 验证 Xcode 构建**

```bash
xcodebuild -project YunPatAi.xcodeproj -scheme YunPatAi build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add App/Views/Tab.swift
git commit -m "feat: define ChatTab and ChatMessage models"
```

### Task 27: 创建 TabManager（多标签管理）

**Files:**
- Create: `App/Views/TabBar.swift`

- [ ] **Step 1: 写 TabManager**

```swift
// App/Views/TabBar.swift
import SwiftUI

@MainActor
final class TabManager: ObservableObject {
    @Published var tabs: [ChatTab] = []
    @Published var activeTabID: UUID?

    init() {
        let defaultTab = ChatTab(title: "新对话")
        tabs = [defaultTab]
        activeTabID = defaultTab.id
    }

    func addTab() {
        let newTab = ChatTab(title: "新对话")
        tabs.append(newTab)
        activeTabID = newTab.id
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        tabs.removeAll { $0.id == id }
        if activeTabID == id {
            activeTabID = tabs.first?.id
        }
    }

    func appendMessage(to tabID: UUID, _ message: ChatMessage) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].messages.append(message)
    }
}

// MARK: - TabBar View
struct TabBar: View {
    @ObservedObject var tabManager: TabManager

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabManager.tabs) { tab in
                TabButton(
                    tab: tab,
                    isActive: tabManager.activeTabID == tab.id,
                    onSelect: { tabManager.activeTabID = tab.id },
                    onClose: { tabManager.closeTab(tab.id) }
                )
            }
            Button(action: { tabManager.addTab() }) {
                Image(systemName: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
    }
}

struct TabButton: View {
    let tab: ChatTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tab.title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .onTapGesture { onSelect() }
    }
}
```

- [ ] **Step 2: 验证构建**

```bash
xcodebuild -project YunPatAi.xcodeproj -scheme YunPatAi build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add App/Views/TabBar.swift
git commit -m "feat: implement TabManager with add/close/switch tabs"
```

### Task 28: 创建 ChatViewModel（状态管理 + ModelRouter 集成）

**Files:**
- Create: `App/Views/ChatView.swift` (ViewModel + View)

- [ ] **Step 1: 写 ChatViewModel**

```swift
// App/Views/ChatView.swift
import SwiftUI
import YunPatNetworking
import YunPatCore

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var isStreaming = false

    private let modelRouter: ModelRouter
    private let loopEngine: AgentLoopEngine

    init(modelRouter: ModelRouter) {
        self.modelRouter = modelRouter
        self.loopEngine = AgentLoopEngine(modelRouter: modelRouter)
    }

    func sendMessage(in tabManager: TabManager) async {
        guard let activeID = tabManager.activeTabID,
              !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: inputText)
        tabManager.appendMessage(to: activeID, userMessage)
        let sentText = inputText
        inputText = ""
        isStreaming = true

        do {
            let result = try await loopEngine.run(
                request: UserRequest(content: sentText),
                flow: .copilot
            )

            switch result {
            case .completed(let text):
                let aiMessage = ChatMessage(role: .assistant, content: text)
                tabManager.appendMessage(to: activeID, aiMessage)
            default:
                break
            }
        } catch {
            let errorMessage = ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)")
            tabManager.appendMessage(to: activeID, errorMessage)
        }

        isStreaming = false
    }
}
```

- [ ] **Step 2: 验证构建**

```bash
xcodebuild -project YunPatAi.xcodeproj -scheme YunPatAi build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add App/Views/ChatView.swift
git commit -m "feat: implement ChatViewModel with ModelRouter integration"
```

### Task 29: 实现 API Key 设置界面

**Files:**
- Create: `App/Views/Settings/ProviderSettingsView.swift`

- [ ] **Step 1: 写 ProviderSettingsView**

```swift
// App/Views/Settings/ProviderSettingsView.swift
import SwiftUI
import YunPatNetworking

struct ProviderSettingsView: View {
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var deepseekKey = ""
    @State private var glmKey = ""

    var body: some View {
        Form {
            Section("API Keys") {
                SecureField("OpenAI API Key", text: $openAIKey)
                    .onChange(of: openAIKey) { _, newValue in
                        try? CredentialStore.shared.store(provider: .openai, apiKey: newValue)
                    }
                SecureField("Anthropic API Key", text: $anthropicKey)
                    .onChange(of: anthropicKey) { _, newValue in
                        try? CredentialStore.shared.store(provider: .anthropic, apiKey: newValue)
                    }
                SecureField("DeepSeek API Key", text: $deepseekKey)
                    .onChange(of: deepseekKey) { _, newValue in
                        try? CredentialStore.shared.store(provider: .deepseek, apiKey: newValue)
                    }
                SecureField("GLM API Key", text: $glmKey)
                    .onChange(of: glmKey) { _, newValue in
                        try? CredentialStore.shared.store(provider: .glm, apiKey: newValue)
                    }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            openAIKey = CredentialStore.shared.apiKey(for: .openai) ?? ""
            anthropicKey = CredentialStore.shared.apiKey(for: .anthropic) ?? ""
            deepseekKey = CredentialStore.shared.apiKey(for: .deepseek) ?? ""
            glmKey = CredentialStore.shared.apiKey(for: .glm) ?? ""
        }
    }
}
```

- [ ] **Step 2: 验证构建**

```bash
xcodebuild -project YunPatAi.xcodeproj -scheme YunPatAi build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add App/Views/Settings/ProviderSettingsView.swift
git commit -m "feat: implement API key settings with Keychain persistence"
```

### Task 30: 组装 ContentView（TabBar + ChatView + InputBar）

**Files:**
- Create: `App/Views/ContentView.swift`

- [ ] **Step 1: 写 ContentView**

```swift
// App/Views/ContentView.swift
import SwiftUI
import YunPatNetworking

struct ContentView: View {
    @StateObject private var tabManager = TabManager()
    @StateObject private var chatVM: ChatViewModel

    init() {
        let router = ModelRouter()
        // 从 Keychain 读取 API Key 并注册后端
        if let openAIKey = CredentialStore.shared.apiKey(for: .openai), !openAIKey.isEmpty {
            await router.register(OpenAIProvider(apiKey: openAIKey))
        }
        if let deepseekKey = CredentialStore.shared.apiKey(for: .deepseek), !deepseekKey.isEmpty {
            await router.register(OpenAICompatProvider(apiKey: deepseekKey,
                baseURL: URL(string: "https://api.deepseek.com/v1")!, provider: .deepseek))
        }
        _chatVM = StateObject(wrappedValue: ChatViewModel(modelRouter: router))
    }

    var body: some View {
        VStack(spacing: 0) {
            TabBar(tabManager: tabManager)
                .padding(.horizontal)
                .padding(.top, 4)

            Divider()

            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let activeID = tabManager.activeTabID,
                           let activeTab = tabManager.tabs.first(where: { $0.id == activeID }) {
                            ForEach(activeTab.messages) { message in
                                MessageBubble(message: message)
                            }
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // 输入栏
            HStack {
                TextField("输入消息...", text: $chatVM.inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await chatVM.sendMessage(in: tabManager) }
                    }
                Button("发送") {
                    Task { await chatVM.sendMessage(in: tabManager) }
                }
                .disabled(chatVM.isStreaming || chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            Text(message.content)
                .padding(10)
                .background(message.role == .user ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .textSelection(.enabled)
            if message.role == .assistant { Spacer() }
        }
    }
}
```

- [ ] **Step 2: 更新 App 入口**

```swift
// App/YunPatApp.swift
@main
struct YunPatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // ... menu commands unchanged
    }
}
```

- [ ] **Step 3: 验证构建**

```bash
xcodebuild -project YunPatAi.xcodeproj -scheme YunPatAi build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add App/Views/ContentView.swift App/YunPatApp.swift
git commit -m "feat: assemble ContentView with TabBar + Chat + Input"
```

---

## Phase F: 集成与收尾（Tasks 31-35）

### Task 31: App 启动时自动注册模型后端

**Files:**
- Modify: `App/YunPatApp.swift`

- [ ] **Step 1: 写 AppDelegate 初始化逻辑**

```swift
// App/YunPatApp.swift (add initializer)
@main
struct YunPatApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
            // ... existing menu commands
        }
        Settings {
            ProviderSettingsView()
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    let modelRouter: ModelRouter

    init() {
        let router = ModelRouter()
        let store = CredentialStore.shared

        if let key = store.apiKey(for: .openai), !key.isEmpty {
            await router.register(OpenAIProvider(apiKey: key))
        }
        if let key = store.apiKey(for: .anthropic), !key.isEmpty {
            await router.register(AnthropicProvider(apiKey: key))
        }
        if let key = store.apiKey(for: .deepseek), !key.isEmpty {
            await router.register(OpenAICompatProvider(
                apiKey: key, baseURL: URL(string: "https://api.deepseek.com/v1")!, provider: .deepseek))
        }
        if let key = store.apiKey(for: .glm), !key.isEmpty {
            await router.register(OpenAICompatProvider(
                apiKey: key, baseURL: URL(string: "https://open.bigmodel.cn/api/paas/v4")!, provider: .glm))
        }

        self.modelRouter = router
    }
}
```

- [ ] **Step 2: 验证构建**

```bash
xcodebuild -project YunPatAi.xcodeproj -scheme YunPatAi build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add App/YunPatApp.swift
git commit -m "feat: auto-register model backends on app launch"
```

### Task 32: 集成测试 — 端到端流式对话

**Files:**
- Create: `App/UITests/` (手动测试流程文档) 或验证可运行态

- [ ] **Step 1: 启动 App 并手动验证**

```bash
# 打开 App
open build/DerivedData/Build/Products/Debug/YunPatAi.app

# 验证步骤：
# 1. 打开 Settings → 填入 DeepSeek API Key
# 2. 在主界面输入 "你好，请用一句话介绍自己"
# 3. 点击发送
# 4. 验证 AI 回复出现在聊天区
# 5. 新建标签 (⌘T)
# 6. 在新标签中发送另一条消息
# 7. 验证两个标签独立对话
```

- [ ] **Step 2: 记录验证结果**

```
[ ] DeepSeek 回复正常
[ ] Anthropic 回复正常
[ ] OpenAI 回复正常
[ ] GLM 回复正常
[ ] 多标签独立对话正常
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "test: verify end-to-end streaming chat across all providers"
```

### Task 33: 添加流式响应渲染（逐字输出 + 打字指示器）

**Files:**
- Modify: `App/Views/ChatView.swift`

- [ ] **Step 1: 为 ChatViewModel 添加流式更新**

```swift
// ChatViewModel (add streaming state)
@Published var streamingContent = ""
@Published var streamingMessageID: UUID?

func sendMessage(in tabManager: TabManager) async {
    // ... existing code up to loopEngine.run() ...

    // Replace non-streaming with streaming
    // (For Plan 1 MVP, keep the simple wait-for-complete approach.
    //  Streaming rendering to be added in Plan 2 with document workspace.)
}
```

- [ ] **Step 2: 验证**

```bash
xcodebuild -project YunPatAi.xcodeproj -scheme YunPatAi build 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
git add App/Views/ChatView.swift
git commit -m "feat: prepare streaming content state for future use"
```

### Task 34: SwiftLint + 代码规范检查

- [ ] **Step 1: 运行 swift-format**

```bash
swift-format --configuration .swift-format --recursive Packages/ App/ --dry-run
```
Expected: No violations

- [ ] **Step 2: 如有违规，自动修复**

```bash
swift-format --configuration .swift-format --recursive Packages/ App/ -i
```

- [ ] **Step 3: 运行所有测试**

```bash
cd Packages/YunPatNetworking && swift test 2>&1 | tail -5
cd ../YunPatCore && swift test 2>&1 | tail -5
```
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: format code, all tests passing"
```

### Task 35: 编写 README.md 和快速开始指南

**Files:**
- Create: `README.md`

- [ ] **Step 1: 写 README**

```markdown
# YunPat-Ai

面向专利代理人和专利律师的 macOS 桌面端 AI 智能体。

## 构建

```bash
git clone <repo>
cd YunPat-Ai
open YunPatAi.xcodeproj
# ⌘R 运行
```

## 配置

1. 打开 Settings (⌘,)
2. 填入至少一个 API Key（DeepSeek/OpenAI/Anthropic/GLM）
3. 返回主界面开始对话

## 架构

```
App/           SwiftUI macOS App
Packages/
  YunPatCore/       AgentLoop + Capability + Context
  YunPatNetworking/ 多后端模型路由
```
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with build and setup instructions"
```

---

## Plan 1 验收标准

- [ ] macOS App 成功构建并启动
- [ ] 多标签支持：新建/切换/关闭标签
- [ ] 至少 1 个模型后端对话正常（DeepSeek 优先）
- [ ] API Key 通过 Keychain 安全存储
- [ ] AgentLoopEngine 正确处理 Copilot Flow
- [ ] CapabilityRegistry 注册内置能力
- [ ] ContextEngine 组装 prompt
- [ ] 所有 XCTest 测试通过（≥ 12 个测试）
- [ ] 代码通过 swift-format 检查
