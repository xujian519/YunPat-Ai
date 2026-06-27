# YunPat-Ai Plan 3: Desktop Integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 桌面自主代理能力——AXorcist 操控 Mac 应用、Shell 执行、文件系统双轨回滚（Git+TimeMachine）、文档工作区分屏标注感知、安全权限体系。

**Architecture:** 新建 YunPatDesktop SPM 包。DesktopAutomationProvider 协议抽象 AXorcist。Git + TimeMachine 双轨版本管理。NSFileCoordinator 锁 + perCall/perSession 权限弹窗。文档工作区在 App/Views 层实现标注语法解析。

**Tech Stack:** Swift 6, AppKit, AXorcist (GitHub), git CLI, FSEvents, NSFileCoordinator, Apple Containerization (macOS 26+)

---

## 文件结构（Plan 3 新增/修改）

```
YunPat-Ai/
├── Packages/
│   └── YunPatDesktop/              ← 新建 SPM 包
│       ├── Package.swift
│       ├── Sources/YunPatDesktop/
│       │   ├── DesktopAutomationProvider.swift  # 协议抽象
│       │   ├── AXorcistProvider.swift           # AXorcist 实现
│       │   ├── ShellExecutor.swift              # Shell 执行
│       │   ├── FileOperator.swift               # 文件操作
│       │   ├── VersionController.swift          # Git + TimeMachine 双轨
│       │   └── SecurityGate.swift               # 权限门禁
│       └── Tests/YunPatDesktopTests/
│           ├── ShellExecutorTests.swift
│           └── VersionControllerTests.swift
├── App/Views/
│   ├── DocumentWorkspace.swift      # 新增：分屏文档工作区
│   ├── DocumentEditor.swift         # 新增：标注感知编辑器
│   └── AnnotationParser.swift       # 新增：{del:}/{ins:}/{???} 解析
```

---

## Phase A: YunPatDesktop 包脚手架 + 协议层（Tasks 1-4）

### Task 1: 创建 YunPatDesktop SPM 包

**Files:**
- Create: `Packages/YunPatDesktop/Package.swift`

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YunPatDesktop",
    platforms: [.macOS(.v15)],
    products: [.library(name: "YunPatDesktop", targets: ["YunPatDesktop"])],
    targets: [
        .target(name: "YunPatDesktop"),
        .testTarget(name: "YunPatDesktopTests", dependencies: ["YunPatDesktop"]),
    ]
)
```

- [ ] **Step 2: Create Sources + Tests skeleton**

```bash
mkdir -p Packages/YunPatDesktop/Sources/YunPatDesktop
mkdir -p Packages/YunPatDesktop/Tests/YunPatDesktopTests
touch Packages/YunPatDesktop/Sources/YunPatDesktop/YunPatDesktop.swift
```

- [ ] **Step 3: Verify build**

```bash
cd Packages/YunPatDesktop && swift build
```
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/YunPatDesktop/
git commit -m "feat: scaffold YunPatDesktop package"
```

### Task 2: 定义 DesktopAutomationProvider 协议

**Files:**
- Create: `Packages/YunPatDesktop/Sources/YunPatDesktop/DesktopAutomationProvider.swift`

- [ ] **Step 1: Write protocol**

```swift
// Packages/YunPatDesktop/Sources/YunPatDesktop/DesktopAutomationProvider.swift
import Foundation

public struct AppIdentifier: Sendable {
    public let bundleID: String
    public let displayName: String
    public init(bundleID: String, displayName: String) { self.bundleID = bundleID; self.displayName = displayName }
}

public struct ElementLocator: Sendable {
    public let role: String
    public let description: String
    public let value: String?
    public init(role: String, description: String = "", value: String? = nil) { self.role = role; self.description = description; self.value = value }
}

public protocol DesktopAutomationProvider: Sendable {
    func click(app: AppIdentifier, element: ElementLocator) async throws
    func type(app: AppIdentifier, text: String, target: ElementLocator) async throws
    func read(app: AppIdentifier, element: ElementLocator) async throws -> String
    func screenshot(app: AppIdentifier?, region: CGRect?) async throws -> Data
    var isAccessibilityEnabled: Bool { get async }
}
```

- [ ] **Step 2: Verify build**

```bash
cd Packages/YunPatDesktop && swift build
```

- [ ] **Step 3: Commit**

### Task 3: 实现 AXorcistProvider（AXorcist 协议实现）

**Files:**
- Create: `Packages/YunPatDesktop/Sources/YunPatDesktop/AXorcistProvider.swift`

- [ ] **Step 1: Write AXorcistProvider**

```swift
// Packages/YunPatDesktop/Sources/YunPatDesktop/AXorcistProvider.swift
import Foundation
import ApplicationServices

public actor AXorcistProvider: DesktopAutomationProvider {
    public init() {}

    public var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    public func click(app: AppIdentifier, element: ElementLocator) async throws {
        guard let appElement = findApp(app) else { throw AXError.appNotFound }
        guard let target = findElement(in: appElement, locator: element) else { throw AXError.elementNotFound }
        let result = AXUIElementPerformAction(target, kAXPressAction as CFString)
        guard result == .success else { throw AXError.actionFailed(result) }
    }

    public func type(app: AppIdentifier, text: String, target: ElementLocator) async throws {
        guard let appElement = findApp(app) else { throw AXError.appNotFound }
        guard let targetElement = findElement(in: appElement, locator: target) else { throw AXError.elementNotFound }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(targetElement, kAXFocusedAttribute as CFString, &value) == .success else {
            throw AXError.elementNotFound
        }
        let result = AXUIElementSetAttributeValue(targetElement, kAXValueAttribute as CFString, text as CFTypeRef)
        guard result == .success else { throw AXError.actionFailed(result) }
    }

    public func read(app: AppIdentifier, element: ElementLocator) async throws -> String {
        guard let appElement = findApp(app) else { throw AXError.appNotFound }
        guard let target = findElement(in: appElement, locator: element) else { throw AXError.elementNotFound }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(target, kAXValueAttribute as CFString, &value)
        guard result == .success else { throw AXError.actionFailed(result) }
        return value as? String ?? ""
    }

    public func screenshot(app: AppIdentifier?, region: CGRect?) async throws -> Data {
        let image = CGDisplayCreateImage(CGMainDisplayID(), rect: region)
        guard let image else { throw AXError.actionFailed(.cannotComplete) }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    // MARK: Private
    private func findApp(_ id: AppIdentifier) -> AXUIElement? {
        let apps = NSWorkspace.shared.runningApplications
        guard let target = apps.first(where: { $0.bundleIdentifier == id.bundleID }) else { return nil }
        return AXUIElementCreateApplication(target.processIdentifier)
    }

    private func findElement(in root: AXUIElement, locator: ElementLocator) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return nil }
        for child in children {
            var role: CFTypeRef?, desc: CFTypeRef?, val: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &desc)
            AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &val)
            let roleStr = (role as? String) ?? ""
            let descStr = (desc as? String) ?? ""
            if roleStr == locator.role && (locator.description.isEmpty || descStr.contains(locator.description)) {
                return child
            }
        }
        return nil
    }
}

public enum AXError: Error {
    case appNotFound
    case elementNotFound
    case actionFailed(AXError)
    var localizedDescription: String {
        switch self {
        case .appNotFound: "应用未运行"
        case .elementNotFound: "UI 元素未找到"
        case .actionFailed: "操作失败"
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd Packages/YunPatDesktop && swift build
```

- [ ] **Step 3: Commit**

### Task 4: 定义 SecurityGate（权限门禁）

**Files:**
- Create: `Packages/YunPatDesktop/Sources/YunPatDesktop/SecurityGate.swift`

- [ ] **Step 1: Write SecurityGate**

```swift
// Packages/YunPatDesktop/Sources/YunPatDesktop/SecurityGate.swift
import Foundation

public enum PermissionLevel: Sendable {
    case always
    case perSession
    case perCall
    case never(denied: true)
}

public struct OperationLog: Sendable {
    public let timestamp: Date
    public let capability: String
    public let tool: String
    public let arguments: String
    public let result: String
    public init(timestamp: Date = Date(), capability: String, tool: String, arguments: String, result: String) {
        self.timestamp = timestamp; self.capability = capability; self.tool = tool; self.arguments = arguments; self.result = result
    }
}

public actor SecurityGate {
    private var sessionGrants: Set<String> = []
    private var callGrants: Set<String> = []
    private var deniedList: Set<String> = []
    public private(set) var auditLog: [OperationLog] = []

    public init() {}

    public func check(_ capability: String, level: PermissionLevel) -> Bool {
        switch level {
        case .always: return true
        case .never: return false
        case .perSession:
            if sessionGrants.contains(capability) { return true }
            // 弹窗请求授权 → 用户确认后加入 sessionGrants
            return false
        case .perCall:
            if callGrants.contains(capability) { callGrants.remove(capability); return true }
            return false
        }
    }

    public func grant(_ capability: String, level: PermissionLevel) {
        switch level {
        case .perSession: sessionGrants.insert(capability)
        case .perCall: callGrants.insert(capability)
        default: break
        }
    }

    public func record(_ log: OperationLog) { auditLog.append(log) }
    public func flushAuditLog() -> [OperationLog] { let log = auditLog; auditLog.removeAll(); return log }
}
```

- [ ] **Step 2: Verify build + Commit**

---

## Phase B: Shell + 文件操作 + Git 版本控制（Tasks 5-9）

### Task 5: 实现 ShellExecutor

**Files:**
- Create: `Packages/YunPatDesktop/Sources/YunPatDesktop/ShellExecutor.swift`

- [ ] **Step 1: Write ShellExecutor**

```swift
// Packages/YunPatDesktop/Sources/YunPatDesktop/ShellExecutor.swift
import Foundation

public struct ShellOutput: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) { self.stdout = stdout; self.stderr = stderr; self.exitCode = exitCode }
}

public actor ShellExecutor {
    private let allowedCommands: Set<String>
    private let gate: SecurityGate

    public init(allowedCommands: Set<String> = ["ls","cat","grep","git","python3","node","swift"], gate: SecurityGate = SecurityGate()) {
        self.allowedCommands = allowedCommands; self.gate = gate
    }

    public func execute(_ command: String, cwd: URL? = nil, timeout: TimeInterval = 30) async throws -> ShellOutput {
        let cmd = command.trimmingCharacters(in: .whitespaces)
        let firstWord = cmd.components(separatedBy: " ").first ?? ""
        guard allowedCommands.contains(firstWord) else {
            throw ShellError.commandNotAllowed(firstWord)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", cmd]
        if let cwd { process.currentDirectoryURL = cwd }

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe; process.standardError = errPipe

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)

        while process.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        if process.isRunning { process.terminate() }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        await gate.record(OperationLog(capability: "shell", tool: "execute", arguments: cmd, result: stdout.prefix(200).description))
        return ShellOutput(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}

public enum ShellError: Error {
    case commandNotAllowed(String)
}
```

- [ ] **Step 2: Verify build + Commit**

### Task 6: 实现 FileOperator（文件系统读写 + NSFileCoordinator 锁）

**Files:**
- Create: `Packages/YunPatDesktop/Sources/YunPatDesktop/FileOperator.swift`

- [ ] **Step 1: Write FileOperator**

```swift
// Packages/YunPatDesktop/Sources/YunPatDesktop/FileOperator.swift
import Foundation

public actor FileOperator {
    private let workspaceRoot: URL
    private let gate: SecurityGate

    public init(workspaceRoot: URL, gate: SecurityGate = SecurityGate()) {
        self.workspaceRoot = workspaceRoot; self.gate = gate
    }

    public func readFile(_ path: String) async throws -> Data {
        let url = resolveURL(path)
        guard isWithinWorkspace(url) else { throw FileError.pathNotAllowed(path) }
        // NSFileCoordinator 读锁
        let coordinator = NSFileCoordinator()
        var result: Data = Data()
        var error: Error?
        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { readURL in
            result = (try? Data(contentsOf: readURL)) ?? Data()
        }
        if let error { throw error }
        return result
    }

    public func writeFile(_ path: String, content: Data) async throws {
        let url = resolveURL(path)
        guard isWithinWorkspace(url) else { throw FileError.pathNotAllowed(path) }
        let coordinator = NSFileCoordinator()
        var error: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { writeURL in
            try? content.write(to: writeURL)
        }
        if let error { throw error }
        await gate.record(OperationLog(capability: "file", tool: "write", arguments: path, result: "ok"))
    }

    public func deleteFile(_ path: String) async throws {
        let url = resolveURL(path)
        guard isWithinWorkspace(url) else { throw FileError.pathNotAllowed(path) }
        try FileManager.default.removeItem(at: url)
    }

    private func resolveURL(_ path: String) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : workspaceRoot.appendingPathComponent(path)
    }

    private func isWithinWorkspace(_ url: URL) -> Bool {
        url.path.hasPrefix(workspaceRoot.path)
    }
}

public enum FileError: Error {
    case pathNotAllowed(String)
}
```

- [ ] **Step 2: Verify build + Commit**

### Task 7: 实现 VersionController（Git 语义化 + TimeMachine 双轨）

**Files:**
- Create: `Packages/YunPatDesktop/Sources/YunPatDesktop/VersionController.swift`
- Create: `Packages/YunPatDesktop/Tests/YunPatDesktopTests/VersionControllerTests.swift`

- [ ] **Step 1: Write test FIRST**

```swift
// Tests/YunPatDesktopTests/VersionControllerTests.swift
import XCTest
@testable import YunPatDesktop

final class VersionControllerTests: XCTestCase {
    func testGitCommit_createsSemanticRecord() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        // Init git
        let shell = ShellExecutor()
        _ = try await shell.execute("cd \(tmpDir.path) && git init && git config user.email test@test.com && git config user.name test", timeout: 10)

        let controller = VersionController(workspaceRoot: tmpDir, shellExecutor: shell)
        let testFile = tmpDir.appendingPathComponent("test.md")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        try await controller.commit(files: ["test.md"], message: "[agent] 测试提交", author: .agent)

        let log = try await controller.gitLog()
        XCTAssertTrue(log.contains("测试提交"))
    }
}
```

- [ ] **Step 2: Run test — FAIL**

- [ ] **Step 3: Write VersionController**

```swift
// Packages/YunPatDesktop/Sources/YunPatDesktop/VersionController.swift
import Foundation

public enum CommitAuthor: String, Sendable {
    case user
    case agent
    case hybrid
}

public actor VersionController {
    private let workspaceRoot: URL
    private let shell: ShellExecutor
    private let snapshotsDir: URL

    public init(workspaceRoot: URL, shellExecutor: ShellExecutor = ShellExecutor()) {
        self.workspaceRoot = workspaceRoot
        self.shell = shellExecutor
        self.snapshotsDir = workspaceRoot.appendingPathComponent(".yunpat/snapshots")
        try? FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
    }

    /// Git 语义化提交
    public func commit(files: [String], message: String, author: CommitAuthor) async throws {
        let fileList = files.joined(separator: " ")
        let fullMsg = "[\(author.rawValue)] \(message)"
        let cmd = "cd \(workspaceRoot.path) && git add \(fileList) && git commit -m '\(fullMsg)'"
        _ = try await shell.execute(cmd, cwd: workspaceRoot, timeout: 10)
    }

    /// TimeMachine 快照（二进制文件）
    public func snapshot(file: String) async throws -> String {
        let snapshotID = UUID().uuidString.prefix(8)
        let src = workspaceRoot.appendingPathComponent(file)
        let dst = snapshotsDir.appendingPathComponent("\(snapshotID)_\(file.components(separatedBy: "/").last!)")
        try FileManager.default.copyItem(at: src, to: dst)
        return String(snapshotID)
    }

    /// 从快照恢复
    public func restoreSnapshot(_ snapshotID: String, to file: String) async throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: snapshotsDir.path)
        guard let match = files.first(where: { $0.hasPrefix(snapshotID) }) else { throw VersionError.snapshotNotFound }
        let src = snapshotsDir.appendingPathComponent(match)
        let dst = workspaceRoot.appendingPathComponent(file)
        try FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: src, to: dst)
    }

    /// Git 日志
    public func gitLog(count: Int = 20) async throws -> String {
        let result = try await shell.execute("cd \(workspaceRoot.path) && git log --oneline -n \(count)", timeout: 5)
        return result.stdout
    }
}

public enum VersionError: Error {
    case snapshotNotFound
}
```

- [ ] **Step 4: Run test — PASS**

- [ ] **Step 5: Commit**

### Task 8: 注册桌面 Capability 到 CapabilityRegistry

**Files:**
- Modify: `Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityRegistry.swift`

- [ ] **Step 1: Register desktop capabilities**

```swift
// Append to registerBuiltinCapabilities():
register(capability: CapabilityDefinition(
    name: "desktop.shell", displayName: "Shell 执行", description: "执行 shell 命令",
    source: .builtin, permission: .perSession,
    metadata: CapabilityMetadata(costLevel: .free, requiresNetwork: false, isIdempotent: false, typicalUseCases: ["脚本执行", "git 操作"])
))
register(capability: CapabilityDefinition(
    name: "desktop.file", displayName: "文件操作", description: "读写工作目录文件",
    source: .builtin, permission: .perSession,
    metadata: CapabilityMetadata(costLevel: .free, requiresNetwork: false, isIdempotent: false, typicalUseCases: ["文件读取", "文件写入"])
))
register(capability: CapabilityDefinition(
    name: "desktop.automation", displayName: "桌面自动化", description: "操控 Mac 应用（AXorcist）",
    source: .builtin, permission: .perCall,
    metadata: CapabilityMetadata(costLevel: .low, requiresNetwork: false, isIdempotent: false, typicalUseCases: ["应用操控", "UI 读取"])
))
```

- [ ] **Step 2: Verify tests**

```bash
cd Packages/YunPatCore && swift test --filter CapabilityRegistryTests
```

- [ ] **Step 3: Commit**

### Task 9: ShellExecutor 测试

**Files:**
- Create: `Packages/YunPatDesktop/Tests/YunPatDesktopTests/ShellExecutorTests.swift`

- [ ] **Step 1: Write test**

```swift
import XCTest
@testable import YunPatDesktop

final class ShellExecutorTests: XCTestCase {
    func testExecute_simpleEcho_returnsOutput() async throws {
        let shell = ShellExecutor()
        let output = try await shell.execute("echo hello", timeout: 5)
        XCTAssertTrue(output.stdout.contains("hello"))
    }

    func testExecute_blockedCommand_throwsError() async throws {
        let shell = ShellExecutor(allowedCommands: ["echo"])
        do {
            _ = try await shell.execute("ls -la", timeout: 5)
            XCTFail("Expected error for blocked command")
        } catch {}
    }
}
```

- [ ] **Step 2: Run test — PASS**

- [ ] **Step 3: Commit**

---

## Phase C: 文档工作区（Tasks 10-14）

### Task 10: 实现 AnnotationParser（标注语法解析）

**Files:**
- Create: `App/Views/AnnotationParser.swift`

- [ ] **Step 1: Write AnnotationParser**

```swift
// App/Views/AnnotationParser.swift
import Foundation

public struct TextEdit: Sendable {
    public let line: Int
    public let oldText: String
    public let newText: String
    public init(line: Int, oldText: String, newText: String) { self.line = line; self.oldText = oldText; self.newText = newText }
}

public struct DocumentAnnotation: Sendable {
    public let line: Int
    public let type: AnnotationType
    public let content: String
    public init(line: Int, type: AnnotationType, content: String) { self.line = line; self.type = type; self.content = content }
}

public enum AnnotationType: String, Sendable {
    case deletion      // {del:原文}
    case insertion     // {ins:新文本}
    case question      // {???} 段落
    case comment       // 💬 行内评论
}

public final class AnnotationParser {
    public func parse(_ text: String) -> (cleanText: String, annotations: [DocumentAnnotation], edits: [TextEdit]) {
        var cleanText = text
        var annotations: [DocumentAnnotation] = []
        var edits: [TextEdit] = []

        let lines = text.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            // {del:原文}
            if let match = parsePattern("{del:", "}", in: line) {
                annotations.append(DocumentAnnotation(line: i + 1, type: .deletion, content: match.content))
                cleanText = cleanText.replacingOccurrences(of: "{del:\(match.content)}", with: match.content)
                if let nextLine = lines.dropFirst(i + 1).first, nextLine.contains("{ins:") {
                    if let ins = parsePattern("{ins:", "}", in: nextLine) {
                        edits.append(TextEdit(line: i + 1, oldText: match.content, newText: ins.content))
                    }
                }
            }
            // {ins:新文本}
            if let match = parsePattern("{ins:", "}", in: line) {
                annotations.append(DocumentAnnotation(line: i + 1, type: .insertion, content: match.content))
                cleanText = cleanText.replacingOccurrences(of: "{ins:\(match.content)}", with: match.content)
            }
            // {???}
            if line.contains("{???}") {
                let content = line.replacingOccurrences(of: "{???}", with: "").trimmingCharacters(in: .whitespaces)
                annotations.append(DocumentAnnotation(line: i + 1, type: .question, content: content))
                cleanText = cleanText.replacingOccurrences(of: "{???}", with: "❓")
            }
        }

        return (cleanText, annotations, edits)
    }

    private func parsePattern(_ open: String, _ close: String, in line: String) -> (content: String)? {
        guard let start = line.range(of: open)?.upperBound,
              let end = line[start...].range(of: close)?.lowerBound else { return nil }
        return (String(line[start..<end]))
    }
}
```

- [ ] **Step 2: Verify build + Commit**

### Task 11: 实现 DocumentWorkspace（分屏 + Chat 联动）

**Files:**
- Create: `App/Views/DocumentWorkspace.swift`

- [ ] **Step 1: Write DocumentWorkspace**

```swift
// App/Views/DocumentWorkspace.swift
import SwiftUI

struct DocumentWorkspace: View {
    @State private var documentText: String = ""
    @State private var annotations: [DocumentAnnotation] = []
    @State private var edits: [TextEdit] = []
    private let parser = AnnotationParser()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("文档工作区").font(.headline)
                Spacer()
                if !annotations.isEmpty {
                    Text("\(annotations.count) 处标注").font(.caption).foregroundStyle(.orange)
                }
            }.padding(.horizontal).padding(.top, 8)

            Divider()

            TextEditor(text: $documentText)
                .font(.system(.body, design: .monospaced))
                .onChange(of: documentText) { _, newValue in
                    let result = parser.parse(newValue)
                    annotations = result.annotations
                    edits = result.edits
                }

            if !annotations.isEmpty {
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(annotations, id: \.line) { ann in
                            AnnotationBadge(annotation: ann)
                        }
                    }.padding(8)
                }
                .frame(height: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackgroundColor)
    }
}

struct AnnotationBadge: View {
    let annotation: DocumentAnnotation
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("L\(annotation.line)").font(.caption2)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color).cornerRadius(12)
        .font(.caption)
    }

    var icon: String {
        switch annotation.type {
        case .deletion: "trash"
        case .insertion: "plus.circle"
        case .question: "questionmark.circle"
        case .comment: "text.bubble"
        }
    }

    var color: Color {
        switch annotation.type {
        case .deletion: Color.red.opacity(0.15)
        case .insertion: Color.green.opacity(0.15)
        case .question: Color.orange.opacity(0.15)
        case .comment: Color.blue.opacity(0.15)
        }
    }
}
```

- [ ] **Step 2: Update ContentView to support split-screen**

```swift
// ContentView — add split-screen toggle
@State private var showDocumentWorkspace = false

// In toolbar:
Button(action: { withAnimation { showDocumentWorkspace.toggle() } }) {
    Image(systemName: "doc.richtext").font(.system(size: 12))
}.buttonStyle(.plain).help("文档工作区")

// Main area changes to HSplitView when document workspace active:
if showDocumentWorkspace {
    HSplitView {
        // Chat column
        VStack { /* existing chat content */ }
        // Document column
        DocumentWorkspace()
    }
} else {
    // existing single-column chat
}
```

- [ ] **Step 3: Verify build + Commit**

### Task 12: 实现 DocumentChangeDetector（FSEvents + Diff）

**Files:**
- Create: `App/Views/DocumentChangeDetector.swift`

- [ ] **Step 1: Write DocumentChangeDetector**

```swift
// App/Views/DocumentChangeDetector.swift
import Foundation

public struct DocumentChangeEvent: Sendable {
    public let document: URL
    public let edits: [TextEdit]
    public let annotations: [DocumentAnnotation]
    public let questions: [String]
    public let timestamp: Date
    public init(document: URL, edits: [TextEdit] = [], annotations: [DocumentAnnotation] = [], questions: [String] = [], timestamp: Date = Date()) {
        self.document = document; self.edits = edits; self.annotations = annotations; self.questions = questions; self.timestamp = timestamp
    }
}

public actor DocumentChangeDetector {
    private let parser = AnnotationParser()
    private var previousContent: [URL: String] = [:]

    public init() {}

    public func detectChanges(in document: URL, currentContent: String) -> DocumentChangeEvent? {
        guard let previous = previousContent[document] else {
            previousContent[document] = currentContent; return nil
        }
        guard previous != currentContent else { return nil }

        let (_, annotations, edits) = parser.parse(currentContent)
        let questions = annotations.filter { $0.type == .question }.map(\.content)
        previousContent[document] = currentContent

        return DocumentChangeEvent(document: document, edits: edits, annotations: annotations, questions: questions)
    }
}
```

- [ ] **Step 2: Verify build + Commit**

---

## Phase D: 集成与收尾（Tasks 13-16）

### Task 13: 端到端验证 — Shell 执行 + 文件操作

- [ ] Run all YunPatDesktop tests
- [ ] Verify ShellExecutor works with real commands
- [ ] Verify FileOperator respects workspace bounds

### Task 14: 文档工作区端到端验证

- [ ] Open split-screen mode
- [ ] Type `{del:原文}` annotation
- [ ] Verify AnnotationParser detects it
- [ ] Verify badge appears

### Task 15: 代码质量检查

```bash
cd Packages/YunPatDesktop && swift build && swift test
cd Packages/YunPatNetworking && swift test
cd Packages/YunPatCore && swift test
```

### Task 16: 更新 README + 最终提交

---

## 验收标准

- [ ] YunPatDesktop 包构建通过
- [ ] ShellExecutor 可执行白名单命令
- [ ] FileOperator 文件隔离（只能读写 workspace 内）
- [ ] VersionController Git commit + TimeMachine snapshot 双轨工作
- [ ] DocumentWorkspace 分屏 + {del:}/{ins:}/{???} 标注解析
- [ ] SecurityGate perSession/perCall 权限门禁
- [ ] AXorcistProvider Accessibility API 协议定义完整
- [ ] 所有测试通过 (≥ 25 tests total across all packages)
