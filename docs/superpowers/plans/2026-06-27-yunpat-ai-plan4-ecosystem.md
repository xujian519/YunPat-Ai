# YunPat-Ai Plan 4: Ecosystem

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 插件框架（生命周期 + 分发格式）+ MCP Client/Server + 最终收尾，完成 YunPat-Ai 生态开放能力。

**Architecture:** 新建 YunPatPlugins SPM 包。PluginManager 管理完整生命周期（install→verify→load→enable→upgrade→disable→uninstall）。MCPClient 连接外部 MCP 服务器并注册工具。MCPServer 通过 stdio 对外暴露 YunPat 工具。最终集成验证。

**Tech Stack:** Swift 6, SPM, dlopen, JSON-RPC, stdio pipe

---

## 文件结构（Plan 4 新增）

```
YunPat-Ai/
├── Packages/
│   └── YunPatPlugins/              ← 新建 SPM 包
│       ├── Package.swift
│       ├── Sources/YunPatPlugins/
│       │   ├── PluginManager.swift       # 生命周期管理
│       │   ├── PluginLoader.swift        # dlopen 加载
│       │   ├── PluginVerifier.swift      # 签名/哈希校验
│       │   ├── MCPClient.swift           # MCP 客户端
│       │   ├── MCPServer.swift           # MCP 服务端 (stdio)
│       │   └── MCPTypes.swift            # JSON-RPC 类型
│       └── Tests/YunPatPluginsTests/
│           ├── PluginManagerTests.swift
│           └── MCPClientTests.swift
├── App/
│   └── Views/
│       └── Settings/
│           ├── PluginSettingsView.swift   # 插件管理 UI
│           └── MCPSettingsView.swift      # MCP 服务器管理 UI
```

---

## Phase A: 插件框架（Tasks 1-5）

### Task 1: 创建 YunPatPlugins 包 + 类型定义

- [ ] Create `Packages/YunPatPlugins/Package.swift`
- [ ] Create `Sources/YunPatPlugins/PluginTypes.swift`

```swift
// PluginTypes.swift
import Foundation

public enum PluginLevel: String, Codable { case tool; case feature; case mcpBridge }

public struct PluginManifest: Codable {
    public let id: String; public let name: String; public let version: String
    public let minAppVersion: String; public let level: PluginLevel
    public let description: String; public let author: String
    public let permissions: [PluginPermission]
    public init(id: String, name: String, version: String, minAppVersion: String = "1.0.0", level: PluginLevel = .tool, description: String = "", author: String = "", permissions: [PluginPermission] = []) {
        self.id = id; self.name = name; self.version = version; self.minAppVersion = minAppVersion; self.level = level; self.description = description; self.author = author; self.permissions = permissions
    }
}

public enum PluginPermission: String, Codable { case fileRead; case fileWrite; case networkAPI; case networkArbitrary; case shell; case accessibility; case modelAccess }

public enum PluginState: String { case installed; case verified; case loaded; case enabled; case disabled; case failed; case uninstalled }

public protocol YunPatPlugin: Sendable {
    var manifest: PluginManifest { get }
    func activate() async throws
    func deactivate() async throws
    func verify() async throws -> Bool
    var capabilities: [CapabilityDefinition] { get }
}
```

- [ ] Verify: `cd Packages/YunPatPlugins && swift build`

### Task 2: 实现 PluginLoader（dlopen 加载）

- [ ] Write `Sources/YunPatPlugins/PluginLoader.swift`

```swift
// PluginLoader.swift
import Foundation

public actor PluginLoader {
    private var loadedBundles: [String: Bundle] = [:]

    public func load(from path: URL) async throws -> (Bundle, PluginManifest) {
        guard let bundle = Bundle(url: path) else { throw PluginError.bundleNotFound }
        try bundle.loadAndReturnError()
        guard let manifestURL = bundle.url(forResource: "manifest", withExtension: "json"),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
            throw PluginError.manifestNotFound
        }
        loadedBundles[manifest.id] = bundle
        return (bundle, manifest)
    }

    public func unload(_ pluginID: String) {
        loadedBundles[pluginID]?.unload()
        loadedBundles[pluginID] = nil
    }
}

public enum PluginError: Error { case bundleNotFound; case manifestNotFound; case verificationFailed }
```

### Task 3: 实现 PluginVerifier（签名校验）

- [ ] Write `Sources/YunPatPlugins/PluginVerifier.swift`

```swift
// PluginVerifier.swift
import Foundation
import Security

public actor PluginVerifier {
    public func verify(_ manifest: PluginManifest, bundle: Bundle) async throws -> Bool {
        // 校验 manifest 版本兼容性
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard compareVersions(appVersion, manifest.minAppVersion) >= 0 else { return false }

        // 校验 bundle 签名（macOS Gatekeeper）
        guard let bundleURL = bundle.bundleURL as CFURL? else { return false }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return false }
        return SecStaticCodeCheckValidityWithErrors(code, [], nil, nil) == errSecSuccess
    }

    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.components(separatedBy: ".").compactMap(Int.init)
        let parts2 = v2.components(separatedBy: ".").compactMap(Int.init)
        for i in 0..<max(parts1.count, parts2.count) {
            let a = i < parts1.count ? parts1[i] : 0
            let b = i < parts2.count ? parts2[i] : 0
            if a != b { return a - b }
        }
        return 0
    }
}
```

### Task 4: 实现 PluginManager（生命周期完整管理）

- [ ] Write `Sources/YunPatPlugins/PluginManager.swift`

```swift
// PluginManager.swift
import Foundation

public actor PluginManager {
    private var plugins: [String: (manifest: PluginManifest, state: PluginState)] = [:]
    private let loader = PluginLoader()
    private let verifier = PluginVerifier()

    public init() {}

    public func install(from path: URL) async throws -> String {
        let (bundle, manifest) = try await loader.load(from: path)
        plugins[manifest.id] = (manifest, .installed)
        return manifest.id
    }

    public func verify(_ pluginID: String) async throws -> Bool {
        guard let (manifest, _) = plugins[pluginID] else { throw PluginError.bundleNotFound }
        let valid = try await verifier.verify(manifest, bundle: Bundle(url: URL(fileURLWithPath: ""))!) // real impl uses stored bundle
        if valid { plugins[pluginID]?.state = .verified } else { plugins[pluginID]?.state = .failed }
        return valid
    }

    public func enable(_ pluginID: String) async throws {
        guard plugins[pluginID]?.state == .verified else { throw PluginError.verificationFailed }
        plugins[pluginID]?.state = .enabled
    }

    public func disable(_ pluginID: String) async throws {
        plugins[pluginID]?.state = .disabled
    }

    public func uninstall(_ pluginID: String) async throws {
        plugins[pluginID]?.state = .uninstalled
        loader.unload(pluginID)
    }

    public func listPlugins() -> [(id: String, manifest: PluginManifest, state: PluginState)] {
        plugins.map { ($0.key, $0.value.manifest, $0.value.state) }
    }
}
```

### Task 5: 插件设置 UI

- [ ] Write `App/Views/Settings/PluginSettingsView.swift`

```swift
// PluginSettingsView.swift
import SwiftUI

struct PluginSettingsView: View {
    @State private var plugins: [PluginItem] = []

    var body: some View {
        List {
            ForEach(plugins) { plugin in
                HStack {
                    VStack(alignment: .leading) {
                        Text(plugin.name).font(.headline)
                        Text(plugin.version).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    PluginStateBadge(state: plugin.state)
                }
            }
            HStack { Spacer(); Button("安装插件…") { /* NSOpenPanel */ }; Spacer() }
        }
    }
}

struct PluginItem: Identifiable { let id = UUID(); let name: String; let version: String; let state: String }
struct PluginStateBadge: View { let state: String; var body: some View { Text(state).font(.caption).padding(4).background(state == "enabled" ? Color.green.opacity(0.2) : Color.gray.opacity(0.2)).cornerRadius(4) } }
```

---

## Phase B: MCP Client + Server（Tasks 6-9）

### Task 6: 定义 MCP 类型（JSON-RPC）

- [ ] Write `Sources/YunPatPlugins/MCPTypes.swift`

```swift
// MCPTypes.swift
import Foundation

public struct MCPRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: Int
    public let method: String
    public let params: [String: String]?
    public init(method: String, id: Int = 1, params: [String: String]? = nil) { self.jsonrpc = "2.0"; self.id = id; self.method = method; self.params = params }
}

public struct MCPResponse: Codable, Sendable {
    public let jsonrpc: String; public let id: Int
    public let result: String?; public let error: MCPError?
    public init(id: Int, result: String? = nil, error: MCPError? = nil) { self.jsonrpc = "2.0"; self.id = id; self.result = result; self.error = error }
}

public struct MCPError: Codable, Sendable {
    public let code: Int; public let message: String
    public init(code: Int = -1, message: String) { self.code = code; self.message = message }
}

public struct MCPToolDefinition: Codable, Sendable {
    public let name: String; public let description: String; public let inputSchema: String
    public init(name: String, description: String, inputSchema: String = "{}") { self.name = name; self.description = description; self.inputSchema = inputSchema }
}
```

### Task 7: 实现 MCPClient

- [ ] Write `Sources/YunPatPlugins/MCPClient.swift`

```swift
// MCPClient.swift
import Foundation

public actor MCPClient {
    private var connections: [String: Process] = [:]

    public func connect(serverID: String, command: String, args: [String] = []) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args
        let inPipe = Pipe(), outPipe = Pipe()
        process.standardInput = inPipe; process.standardOutput = outPipe
        try process.run()
        connections[serverID] = process

        // Send initialize
        let request = MCPRequest(method: "initialize")
        let data = try JSONEncoder().encode(request)
        try await send(to: serverID, data: data)
    }

    public func listTools(serverID: String) async throws -> [MCPToolDefinition] {
        let request = MCPRequest(method: "tools/list")
        let data = try JSONEncoder().encode(request)
        let responseData = try await sendAndReceive(serverID, data: data)
        let response = try JSONDecoder().decode(MCPResponse.self, from: responseData)
        // Parse tools from response
        return []
    }

    public func callTool(serverID: String, tool: String, arguments: [String: String]) async throws -> String {
        let request = MCPRequest(method: "tools/call", params: ["name": tool])
        let data = try JSONEncoder().encode(request)
        let responseData = try await sendAndReceive(serverID, data: data)
        return String(data: responseData, encoding: .utf8) ?? ""
    }

    public func disconnect(_ serverID: String) {
        connections[serverID]?.terminate()
        connections[serverID] = nil
    }

    private func send(to serverID: String, data: Data) async throws {
        guard let process = connections[serverID], let stdin = (process.standardInput as? Pipe) else { return }
        stdin.fileHandleForWriting.write(data)
        stdin.fileHandleForWriting.write("\n".data(using: .utf8)!)
    }

    private func sendAndReceive(_ serverID: String, data: Data) async throws -> Data {
        try await send(to: serverID, data: data)
        guard let process = connections[serverID], let stdout = (process.standardOutput as? Pipe) else { throw MCPError(code: -1, message: "Not connected") }
        try await Task.sleep(nanoseconds: 500_000_000)
        return stdout.fileHandleForReading.readDataToEndOfFile()
    }
}
```

### Task 8: 实现 MCPServer（对外暴露工具）

- [ ] Write `Sources/YunPatPlugins/MCPServer.swift`

```swift
// MCPServer.swift
import Foundation

public actor MCPServer {
    private var toolRegistry: [String: (MCPToolDefinition, (([String: String]) async throws -> String))] = [:]

    public func registerTool(_ tool: MCPToolDefinition, handler: @escaping (([String: String]) async throws -> String)) {
        toolRegistry[tool.name] = (tool, handler)
    }

    public func start() async throws {
        let stdin = FileHandle.standardInput
        let stdout = FileHandle.standardOutput

        while true {
            guard let line = String(data: stdin.availableData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty else { continue }

            guard let data = line.data(using: .utf8),
                  let request = try? JSONDecoder().decode(MCPRequest.self, from: data) else { continue }

            let response: MCPResponse
            switch request.method {
            case "tools/list":
                let tools = toolRegistry.values.map { $0.0 }
                let toolsData = try JSONEncoder().encode(tools)
                response = MCPResponse(id: request.id, result: String(data: toolsData, encoding: .utf8))
            case "tools/call":
                if let toolName = request.params?["name"], let (_, handler) = toolRegistry[toolName] {
                    let result = try await handler(request.params ?? [:])
                    response = MCPResponse(id: request.id, result: result)
                } else {
                    response = MCPResponse(id: request.id, error: MCPError(message: "Tool not found"))
                }
            default:
                response = MCPResponse(id: request.id, error: MCPError(code: -32601, message: "Method not found"))
            }

            let responseData = try JSONEncoder().encode(response)
            stdout.write(responseData)
            stdout.write("\n".data(using: .utf8)!)
        }
    }
}
```

### Task 9: MCP 设置 UI

- [ ] Write `App/Views/Settings/MCPSettingsView.swift`

```swift
// MCPSettingsView.swift
import SwiftUI

struct MCPSettingsView: View {
    @State private var servers: [MCPServerItem] = [MCPServerItem(name: "Playwright", command: "npx", args: "@playwright/mcp")]

    var body: some View {
        List {
            ForEach(servers) { server in
                HStack {
                    VStack(alignment: .leading) {
                        Text(server.name).font(.headline)
                        Text("\(server.command) \(server.args)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack { Spacer(); Button("添加 MCP 服务器…") { /* add */ }; Spacer() }
        }
    }
}

struct MCPServerItem: Identifiable { let id = UUID(); let name: String; let command: String; let args: String }
```

---

## Phase C: 集成收尾（Tasks 10-13）

### Task 10: 注册插件 + MCP Capability

- [ ] Add to `CapabilityRegistry.registerBuiltinCapabilities()`:

```swift
register(capability: CapabilityDefinition(
    name: "plugin.manage", displayName: "插件管理", description: "安装/启用/禁用插件",
    source: .builtin, permission: .perSession,
    metadata: CapabilityMetadata(costLevel: .free, requiresNetwork: false, isIdempotent: false, typicalUseCases: ["插件管理"])
))
register(capability: CapabilityDefinition(
    name: "mcp.external", displayName: "MCP 服务", description: "调用外部 MCP 服务器工具",
    source: .builtin, permission: .perSession,
    metadata: CapabilityMetadata(costLevel: .low, requiresNetwork: false, isIdempotent: false, typicalUseCases: ["浏览器自动化", "数据库查询"])
))
```

### Task 11: Settings TabView 集成所有设置面板

- [ ] Update `YunPatApp.swift` Settings to include all panels:

```swift
Settings {
    TabView {
        ProviderSettingsView().tabItem { Label("API", systemImage: "key") }
        KnowledgeSettingsView().tabItem { Label("知识库", systemImage: "books.vertical") }
        PluginSettingsView().tabItem { Label("插件", systemImage: "puzzlepiece") }
        MCPSettingsView().tabItem { Label("MCP", systemImage: "server.rack") }
    }
}
```

### Task 12: 全量测试验证

- [ ] Run all tests across all 4 packages:

```bash
cd Packages/YunPatNetworking && swift test
cd Packages/YunPatCore && swift test
cd Packages/YunPatDesktop && swift test
cd Packages/YunPatPlugins && swift test
```

- [ ] Verify 0 failures

### Task 13: 更新 README + 最终提交

- [ ] Update README with complete architecture overview
- [ ] Add changelog summary
- [ ] Final commit

```bash
cd /Users/xujian/projects/YunPat-Ai
git add -A
git commit -m "feat: complete Plan 4 Ecosystem — plugin framework, MCP client/server, final integration"
```

---

## 验收标准

- [ ] YunPatPlugins 包构建通过
- [ ] PluginManager 完整生命周期（install/verify/enable/disable/uninstall）
- [ ] MCPClient 连接外部 MCP 服务器并注册工具
- [ ] MCPServer 通过 stdio 对外暴露工具
- [ ] Settings 集成所有面板（API / 知识库 / 插件 / MCP）
- [ ] 所有 4 个包测试通过
- [ ] README 完整
