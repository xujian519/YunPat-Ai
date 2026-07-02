# Osaurus Tools 工程体系全面引入计划

> **目标用户:** 子代理执行者，每次执行一个任务
> **执行方式:** 推荐使用 `superpowers:subagent-driven-development` 逐任务分派，或 `superpowers:executing-plans` 内联执行
> **前提:** 步骤使用 `- [ ]` checkbox 语法跟踪

**目标:** 将 Osaurus Tools Master 项目的工具工程化五件套（结构化信封、per-tool AI 指导、CI 校验、SSR 防护、多格式日期解析）以及三件工程基础设施（注册表同步、声明式 secrets、manifest 签名）全面引入 YunPat-Ai。

**架构:** 不改动现有 Loop 驱动和 PatentToolLoop 架构。新增独立文件/目录，在 ToolDispatch、PluginTypes、CapabilityRegistry 三个点做向后兼容扩展。CI 脚本与代码平级独立。

**技术栈:** Swift 6 + Foundation，零外部依赖。Python 3 用于 CI 校验脚本（跟随 Osaurus 模式）。

---

## 文件结构总图

```
新增文件:
  Packages/YunPatCore/Sources/YunPatCore/Tools/
    ToolResponse.swift              ← 标准化工具响应信封 (ok/data/error 三态)
    ToolErrorCode.swift             ← 结构化错误码枚举
    TOOL.md 模板                     ← per-tool AI 指导模板 (后续每个工具补)
  Packages/YunPatCore/Sources/YunPatCore/Tools/Docs/
    patent_search.md                ← patent_search 工具 AI 指导
    legal_status_query.md           ← legal_status_query 工具 AI 指导
    knowledge_search.md             ← knowledge_search 工具 AI 指导
    read_file.md                    ← read_file 工具 AI 指导
    write_file.md                   ← write_file 工具 AI 指导
    execute_shell.md                ← execute_shell 工具 AI 指导
    file_undo.md                    ← file_undo 工具 AI 指导
    file_operation_history.md       ← file_operation_history 工具 AI 指导
    capabilities_discover.md        ← capabilities_discover 工具 AI 指导
    capabilities_load.md            ← capabilities_load 工具 AI 指导
    list_files.md                   ← list_files 工具 AI 指导
    search_files.md                 ← search_files 工具 AI 指导
  Packages/YunPatCore/Sources/YunPatCore/SSR/
    SSRGuard.swift                  ← SSR 防护（IPv4/IPv6 双重检测）
  Packages/YunPatCore/Sources/YunPatCore/Utils/
    DateParser.swift                ← 多格式日期解析（ISO 8601/RFC 2822/Unix）
  Packages/YunPatPlugins/Sources/YunPatPlugins/
    PluginSecrets.swift             ← 声明式 secrets 配置
  scripts/
    validate-tools.swift            ← CI 工具注册校验脚本
    sync-plugin-registry.swift      ← 注册表自动同步脚本

修改文件:
  Packages/YunPatCore/Sources/YunPatCore/Loop/
    ToolDispatch.swift              ← ToolHandlerResult → ToolResponse 迁移
    PatentToolLoop.swift            ← ToolEnvelope 扩展 error 字段
  Packages/YunPatCore/Sources/YunPatCore/Capability/
    ToolDefinition.swift            ← 增 usageGuide 字段
    CapabilityRegistry.swift        ← 增 loadUsageGuide() 方法
  Packages/YunPatPlugins/Sources/YunPatPlugins/
    PluginTypes.swift               ← PluginManifest 增 sha256/signature/secrets
  Packages/YunPatCore/Sources/YunPatCore/Runtime/
    AgentScheduler.swift            ← ToolDispatcher 协议不变（dispatch 仍返回 ToolHandlerResult）
```

---

## 第一部分：核心工程体系（P0）

### 任务 1: 标准化工具响应信封 `ToolResponse`

**文件:**
- 创建: `Packages/YunPatCore/Sources/YunPatCore/Tools/ToolResponse.swift`
- 创建: `Packages/YunPatCore/Sources/YunPatCore/Tools/ToolErrorCode.swift`
- 修改: `Packages/YunPatCore/Sources/YunPatCore/Loop/ToolDispatch.swift:19-29` (ToolHandlerResult)
- 修改: `Packages/YunPatCore/Sources/YunPatCore/Loop/PatentToolLoop.swift:151-158` (ToolEnvelope)

**步骤:**

- [ ] **步骤 1: 编写 ToolResponse / ToolErrorCode 测试**

```swift
// Tests/YunPatCoreTests/ToolResponseTests.swift
import XCTest
@testable import YunPatCore

final class ToolResponseTests: XCTestCase {
    func testSuccessResponse_isOk() {
        let r = ToolResponse.ok(data: .string("hello"))
        XCTAssertTrue(r.ok)
        XCTAssertNil(r.error)
        XCTAssertEqual(r.data, .string("hello"))
    }

    func testErrorResponse_isNotOk() {
        let r = ToolResponse.error(code: .notFound, message: "file missing")
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.error?.code, "NOT_FOUND")
        XCTAssertEqual(r.error?.message, "file missing")
    }

    func testErrorResponseWithHint() {
        let r = ToolResponse.error(code: .ssrfBlocked, message: "Loopback blocked", hint: "Set allow_private: true")
        XCTAssertEqual(r.error?.hint, "Set allow_private: true")
    }

    func testWarningCarriedOnSuccess() {
        let r = ToolResponse.ok(data: .string("done"), warnings: ["deprecated param ignored"])
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.warnings?.count, 1)
    }

    func testJsonRoundtrip() throws {
        let r = ToolResponse.ok(data: .object(["count": .number(5), "results": .array([.string("a"), .string("b")])]))
        let json = r.jsonString()
        let decoded = try JSONDecoder().decode(ToolResponse.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.ok)
    }

    func testErrorDeserialization() throws {
        let json = #"{"ok":false,"error":{"code":"SSRF_BLOCKED","message":"Private IP blocked"},"data":null,"warnings":null}"#
        let decoded = try JSONDecoder().decode(ToolResponse.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.ok)
        XCTAssertEqual(decoded.error?.code, "SSRF_BLOCKED")
    }
}
```

- [ ] **步骤 2: 运行测试验证失败**

```bash
cd Packages/YunPatCore && swift test --filter ToolResponseTests
```
预期: 编译失败 — `ToolResponse` / `ToolErrorCode` 未定义。

- [ ] **步骤 3: 实现 ToolResponse.swift**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Tools/ToolResponse.swift
import Foundation

/// 统一工具响应信封 — 对齐 Osaurus {ok, data} / {ok:false, error} 模式
/// 模型通过 ok 字段精准判断成功/失败，避免散文本误判
public struct ToolResponse: Sendable, Codable {
    public let ok: Bool
    public let data: JSONValue?
    public let error: ToolError?
    public let warnings: [String]?

    public struct ToolError: Sendable, Codable {
        public let code: String
        public let message: String
        public let hint: String?
    }

    public static func ok(data: JSONValue, warnings: [String]? = nil) -> ToolResponse {
        ToolResponse(ok: true, data: data, error: nil, warnings: warnings)
    }

    public static func error(code: ToolErrorCode, message: String, hint: String? = nil) -> ToolResponse {
        ToolResponse(ok: false, data: nil, error: ToolError(code: code.rawValue, message: message, hint: hint), warnings: nil)
    }

    public func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return #"{"ok":false,"error":{"code":"INTERNAL","message":"JSON encode failed"}}"# }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// 递归 JSON 值类型，避免 Any 的非 Codable 问题
public enum JSONValue: Sendable, Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(_ value: some Codable & Sendable) {
        if let encodable = value as? any Encodable {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(AnyEncodable(encodable)),
                  let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                self = .null; return
            }
            self = decoded
        } else {
            self = .null
        }
    }
}

private struct AnyEncodable: Encodable {
    let base: any Encodable
    init(_ base: any Encodable) { self.base = base }
    func encode(to encoder: Encoder) throws { try base.encode(to: encoder) }
}
```

- [ ] **步骤 4: 实现 ToolErrorCode.swift**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Tools/ToolErrorCode.swift
import Foundation

/// 工具层结构化错误码 — 对齐 Osaurus 模式，所有工具统一使用
public enum ToolErrorCode: String, Sendable, Codable {
    // 通用
    case invalidArgs = "INVALID_ARGS"
    case notFound = "NOT_FOUND"
    case timeout = "TIMEOUT"
    case internalError = "INTERNAL"
    case unknownTool = "UNKNOWN_TOOL"

    // 网络
    case ssrfBlocked = "SSRF_BLOCKED"
    case dnsError = "DNS"
    case networkError = "NETWORK"
    case httpError = "HTTP_ERROR"
    case responseTooLarge = "RESPONSE_TOO_LARGE"

    // 文件
    case readError = "READ_ERROR"
    case writeError = "WRITE_ERROR"
    case downloadPathInvalid = "DOWNLOAD_PATH_INVALID"

    // 专利/业务
    case noResults = "NO_RESULTS"
    case providerUnavailable = "PROVIDER_UNAVAILABLE"

    // 其他
    case extractionFailed = "EXTRACTION_FAILED"
    case permissionDenied = "PERMISSION_DENIED"
}
```

- [ ] **步骤 5: 运行测试验证通过**

```bash
cd Packages/YunPatCore && swift test --filter ToolResponseTests
```
预期: 7 个测试全部 PASS。

- [ ] **步骤 6: 扩展 ToolEnvelope 增加 error 结构化字段（向后兼容）**

在 `PatentToolLoop.swift` 中找到 `ToolEnvelope` 定义（约第 151 行），扩展：

```swift
public struct ToolEnvelope: Sendable {
    public let toolName: String
    public let content: String
    public let kind: ToolResultKind
    public let isError: Bool
    // 新增字段
    public let errorCode: String?        // nil 表示非错误
    public let errorHint: String?        // 可选的修复建议
    public let warnings: [String]?       // 非致命警告

    public init(toolName: String, content: String, kind: ToolResultKind = .other,
                isError: Bool = false, errorCode: String? = nil, errorHint: String? = nil,
                warnings: [String]? = nil) {
        self.toolName = toolName
        self.content = content
        self.kind = kind
        self.isError = isError
        self.errorCode = errorCode
        self.errorHint = errorHint
        self.warnings = warnings
    }

    /// 从 ToolResponse 构造（新路径）
    public init(from response: ToolResponse, toolName: String) {
        self.toolName = toolName
        self.content = response.jsonString()
        self.kind = response.ok ? .other : .error
        self.isError = !response.ok
        self.errorCode = response.error?.code
        self.errorHint = response.error?.hint
        self.warnings = response.warnings
    }
}
```

- [ ] **步骤 7: 改造 ToolDispatch.executeCall 支持 ToolResponse**

在 `ToolDispatch.swift` 的 `executeCall` 方法（约第 119 行），增加 `ToolResponse` 路径：

```swift
public static func executeCall(_ call: ToolCall, ctx: ToolContext) async -> ToolEnvelope {
    let input = call.arguments.reduce(into: [String: Any]()) { $0[$1.key] = $1.value }
    let result = await shared.dispatchWithHooks(name: call.name, input: input, ctx: ctx)
    switch result {
    case .handled(let text):
        // 尝试解析为 ToolResponse JSON
        if let data = text.data(using: .utf8),
           let response = try? JSONDecoder().decode(ToolResponse.self, from: data) {
            return ToolEnvelope(from: response, toolName: call.name)
        }
        return ToolEnvelope(toolName: call.name, content: text)
    case .taskComplete(let summary):
        return ToolEnvelope(toolName: call.name, content: summary)
    case .alreadyAppended:
        return ToolEnvelope(toolName: call.name, content: "processed")
    case .notHandled:
        return ToolEnvelope(toolName: call.name, content: "Unknown tool: \(call.name)",
                            isError: true, errorCode: ToolErrorCode.unknownTool.rawValue)
    }
}
```

- [ ] **步骤 8: 更新 handleWriteFile 使用 ToolResponse**

在 `handleWriteFile`（约第 203 行），将 `.handled("Error: ...")` 改为 `.handled(ToolResponse.error(...).jsonString())`：

```swift
private static func handleWriteFile(name: String, input: [String: Any], ctx: ToolContext) async -> ToolHandlerResult {
    let path = input["path"] as? String ?? input["file_path"] as? String ?? ""
    let content = input["content"] as? String ?? ""
    let dryRun = input["dry_run"] as? Bool ?? false
    guard !path.isEmpty else {
        return .handled(ToolResponse.error(code: .invalidArgs, message: "path required").jsonString())
    }

    if dryRun {
        return .handled(ToolResponse.ok(data: .object([
            "dryRun": .bool(true), "path": .string(path), "size": .number(Double(content.count))
        ])).jsonString())
    }

    let beforeContent = try? String(contentsOfFile: path, encoding: .utf8)
    do {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        await FileOperationLog.shared.logWrite(path: path, content: content, beforeContent: beforeContent)
        return .handled(ToolResponse.ok(data: .object([
            "path": .string(path), "size": .number(Double(content.count))
        ])).jsonString())
    } catch {
        return .handled(ToolResponse.error(code: .writeError,
            message: error.localizedDescription, hint: "Check permissions").jsonString())
    }
}
```

- [ ] **步骤 9: 运行现有测试确保无回归**

```bash
cd Packages/YunPatCore && swift test
```
预期: 所有现有测试通过（ToolEnvelope init 兼容旧代码）。

- [ ] **步骤 10: 提交**

```bash
git add Packages/YunPatCore/Sources/YunPatCore/Tools/ToolResponse.swift \
        Packages/YunPatCore/Sources/YunPatCore/Tools/ToolErrorCode.swift \
        Packages/YunPatCore/Sources/YunPatCore/Loop/ToolDispatch.swift \
        Packages/YunPatCore/Sources/YunPatCore/Loop/PatentToolLoop.swift \
        Tests/YunPatCoreTests/ToolResponseTests.swift
git commit -m "feat: add standardized ToolResponse envelope with structured error codes"
```

---

### 任务 2: Per-Tool AI 指导文档 `TOOL.md`

**文件:**
- 创建: `Packages/YunPatCore/Sources/YunPatCore/Tools/Docs/TOOL_TEMPLATE.md`
- 创建: 12 个 `Tools/Docs/<tool_name>.md`

**步骤:**

- [ ] **步骤 1: 编写 TOOL_TEMPLATE.md**

```markdown
---
name: <tool_name>
description: <一句话描述工具功能>
version: "1.0"
author: YunPat Team
---

# <Tool Display Name>

<Tool 核心功能 — 一句话>

## 何时使用

- ✅ <场景 1>
- ✅ <场景 2>
- ❌ <不应使用的场景>

## 典型工作流

```
1. <前置步骤>
2. <调用本工具> → <预期返回值>
3. <后续步骤>
```

## 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `<name>` | `<type>` | ✅/❌ | `<描述>` |

## 返回值

成功: `{ "ok": true, "data": { ... } }`
失败: `{ "ok": false, "error": { "code": "...", "message": "...", "hint": "..." } }`

### 成功时 data 结构

```json
{
  "field": "description"
}
```

### 错误码

| Code | 含义 |
|---|---|
| `INVALID_ARGS` | 参数缺失或格式错误 |
| ...

## 提示

- <Tip 1>
- <Tip 2>

## 已知限制

- <Limitation 1>
```

- [ ] **步骤 2: 编写 patent_search.md AI 指导**

```markdown
---
name: patent_search
description: 专利多源检索工具，覆盖 CNIPA、Google Patents 等
version: "1.0"
author: YunPat Team
---

# 专利检索 (patent_search)

检索中国及国际专利数据库。

## 何时使用

- ✅ 检索某个技术领域的现有专利
- ✅ 查找特定申请人/发明人的专利
- ✅ 为新颖性判断收集对比文献
- ❌ 不用于查询专利法律状态（用 legal_status_query）
- ❌ 不用于纯文本全网搜索（用 knowledge_search）

## 典型工作流

```
1. 从技术方案中提取检索要素（关键词/分类号/申请人）
2. patent_search(query=检索式) → { ok: true, data: { results: [...], count: N } }
3. 对相关结果逐条分析
```

## 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `query` | string | ✅ | 检索式，支持 AND/OR/NOT 布尔运算 |
| `source` | string | ❌ | 检索源，默认 "all"，可选 "cnipa"/"google"/"soopat" |
| `limit` | number | ❌ | 最大返回条数，默认 20 |
| `date_from` | string | ❌ | 起始日期，ISO 8601 格式 |
| `date_to` | string | ❌ | 截止日期，ISO 8601 格式 |
| `category` | string | ❌ | IPC 分类号 |

## 返回值

成功:
```json
{
  "ok": true,
  "data": {
    "query": "机器学习 AND 专利代理",
    "source": "all",
    "count": 15,
    "results": [
      {
        "rank": 1,
        "title": "一种基于机器学习的专利文书自动生成方法",
        "patent_number": "CN202410123456.7",
        "applicant": "某某公司",
        "abstract": "...",
        "publication_date": "2024-03-15",
        "source": "cnipa"
      }
    ]
  }
}
```

失败:
```json
{
  "ok": false,
  "error": { "code": "NO_RESULTS", "message": "未找到匹配专利", "hint": "尝试缩短检索式或更换关键词" },
  "data": { "attempts": [{"source": "cnipa", "ok": false, "error": "no matches"}] }
}
```

## 错误码

| Code | 含义 |
|---|---|
| `INVALID_ARGS` | query 为空或检索式语法错误 |
| `NO_RESULTS` | 无匹配结果 |
| `PROVIDER_UNAVAILABLE` | 检索源不可用 |
| `NETWORK` | 网络请求失败 |
| `TIMEOUT` | 检索超时 |

## 提示

- 先用宽泛的关键词搜索，再逐步收窄
- 中文专利优先用 CNIPA，英文用 Google Patents
- 分类号比关键词更精确——先确定 IPC 再搜
- 返回 0 结果时不要立即放弃，尝试同义词、上位/下位概念

## 已知限制

- CNIPA 数据有 1-2 周延迟
- Google Patents 中国专利的机器翻译质量参差不齐
- SooPAT 偶尔需要验证码
```

- [ ] **步骤 3: 编写其余 11 个工具的 TOOL.md**

依次创建以下文件，内容遵循模板，聚焦工具的输入输出契约、错误码和专利场景提示：
- `legal_status_query.md` — 法律状态查询（CNIPA 公布公告）
- `knowledge_search.md` — 知识库全文检索（法规/判例）
- `read_file.md` — 文件读取
- `write_file.md` — 文件写入（含 FileOperationLog 说明）
- `execute_shell.md` — Shell 命令执行（含安全 warnings）
- `file_undo.md` — 文件撤销（会话内精确回退）
- `file_operation_history.md` — 操作历史查看
- `capabilities_discover.md` — 能力发现（RAG 检索）
- `capabilities_load.md` — 能力加载（按需 schema 更新）
- `list_files.md` — 目录列表
- `search_files.md` — 文件内容搜索
- `list_tools.md` — 工具列表（元工具）

> 详细内容省略——每个 30-60 行，格式与 patent_search.md 一致。

- [ ] **步骤 4: 运行测试确保无破坏**

```bash
cd Packages/YunPatCore && swift test
```
预期: 全部通过（新增 .md 文件不影响编译/测试）。

- [ ] **步骤 5: 提交**

```bash
git add Packages/YunPatCore/Sources/YunPatCore/Tools/Docs/
git commit -m "feat: add per-tool AI guidance docs (TOOL.md) for all 12 built-in tools"
```

---

### 任务 3: 扩展 ToolDefinition 读取 TOOL.md

**文件:**
- 修改: `Packages/YunPatCore/Sources/YunPatCore/Capability/ToolDefinition.swift`
- 修改: `Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityRegistry.swift`

**步骤:**

- [ ] **步骤 1: 编写 CapabilityRegistry 加载 TOOL.md 测试**

```swift
// Tests/YunPatCoreTests/ToolUsageGuideTests.swift
import XCTest
@testable import YunPatCore

final class ToolUsageGuideTests: XCTestCase {
    func testRegistryLoadsUsageGuide() {
        let registry = CapabilityRegistry()
        let guide = registry.usageGuide(for: "patent_search")
        XCTAssertNotNil(guide)
        XCTAssertTrue(guide!.contains("典型工作流"))
    }

    func testMissingToolReturnsNil() {
        let registry = CapabilityRegistry()
        XCTAssertNil(registry.usageGuide(for: "nonexistent_tool"))
    }
}
```

- [ ] **步骤 2: 运行测试验证失败**

```bash
cd Packages/YunPatCore && swift test --filter ToolUsageGuideTests
```
预期: 编译失败 — `usageGuide(for:)` 不存在。

- [ ] **步骤 3: 扩展 ToolDefinition 增加 usageGuide 字段**

```swift
// 在 ToolDefinition.swift 末尾追加
public struct ToolDefinition: Codable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let parameters: String
    public let source: ToolSource
    public let permission: ToolPermission
    // 新增
    public let usageGuide: String?       // per-tool AI 指导 markdown 文本

    public init(name: String, displayName: String, description: String,
                parameters: String = "{}", source: ToolSource = .builtin,
                permission: ToolPermission = .always, usageGuide: String? = nil) {
        self.name = name; self.displayName = displayName; self.description = description
        self.parameters = parameters; self.source = source; self.permission = permission
        self.usageGuide = usageGuide
    }
}
```

- [ ] **步骤 4: 给 CapabilityRegistry 添加 usageGuide(for:) 方法**

```swift
// 在 CapabilityRegistry.swift 末尾追加
import Foundation

extension CapabilityRegistry {
    private static let toolDocsDir: URL = {
        // 获取当前源文件所在目录，然后定位到 Tools/Docs/
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tools/Docs")
    }()

    /// 根据工具名加载对应的 TOOL.md 内容
    public func usageGuide(for toolName: String) -> String? {
        let docURL = Self.toolDocsDir.appendingPathComponent("\(toolName).md")
        guard FileManager.default.fileExists(atPath: docURL.path),
              let content = try? String(contentsOf: docURL, encoding: .utf8) else {
            return nil
        }
        return content
    }
}
```

- [ ] **步骤 5: 在 system prompt 中注入工具指导（ContextEngine 修改）**

在 `ContextEngine.buildPrompt` 的工具集描述块中，读取 `usageGuide(for:)` 并拼接：

```swift
// ContextEngine.swift 中 buildPrompt 的工具集部分追加:
let toolGuides = toolNames.compactMap { name -> String? in
    guard let guide = registry.usageGuide(for: name) else { return nil }
    // 只取前 15 行避免 system prompt 过长
    let lines = guide.split(separator: "\n", maxSplits: 15, omittingEmptySubsequences: false)
    return "### \(name)\n" + lines.prefix(15).joined(separator: "\n")
}.joined(separator: "\n\n")
if !toolGuides.isEmpty {
    prompt.append("\n\n## 工具使用指南\n\(toolGuides)")
}
```

- [ ] **步骤 6: 运行测试验证通过**

```bash
cd Packages/YunPatCore && swift test --filter ToolUsageGuideTests
```
预期: 2 个测试 PASS。

- [ ] **步骤 7: 提交**

```bash
git add Packages/YunPatCore/Sources/YunPatCore/Capability/ToolDefinition.swift \
        Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityRegistry.swift \
        Tests/YunPatCoreTests/ToolUsageGuideTests.swift
git commit -m "feat: load per-tool usage guide from TOOL.md into system prompt"
```

---

### 任务 4: SSR 防护 (`SSRGuard`)

**文件:**
- 创建: `Packages/YunPatCore/Sources/YunPatCore/SSR/SSRGuard.swift`
- 创建: `Tests/YunPatCoreTests/SSRGuardTests.swift`

**步骤:**

- [ ] **步骤 1: 编写 SSR 防护测试**

```swift
// Tests/YunPatCoreTests/SSRGuardTests.swift
import XCTest
@testable import YunPatCore

final class SSRGuardTests: XCTestCase {
    func testBlocksLoopbackIPv4() {
        XCTAssertTrue(SSRGuard.isPrivateIPv4("127.0.0.1"))
        XCTAssertTrue(SSRGuard.isPrivateIPv4("127.255.255.255"))
    }

    func testBlocksRFC1918() {
        XCTAssertTrue(SSRGuard.isPrivateIPv4("10.0.0.1"))
        XCTAssertTrue(SSRGuard.isPrivateIPv4("172.16.0.1"))
        XCTAssertTrue(SSRGuard.isPrivateIPv4("192.168.1.1"))
    }

    func testBlocksLinkLocal() {
        XCTAssertTrue(SSRGuard.isPrivateIPv4("169.254.1.1"))
    }

    func testAllowsPublicIPv4() {
        XCTAssertFalse(SSRGuard.isPrivateIPv4("8.8.8.8"))
        XCTAssertFalse(SSRGuard.isPrivateIPv4("1.1.1.1"))
    }

    func testBlocksLoopbackIPv6() {
        XCTAssertTrue(SSRGuard.isReservedIPv6("::1"))
    }

    func testBlocksLinkLocalIPv6() {
        XCTAssertTrue(SSRGuard.isReservedIPv6("fe80::1"))
    }

    func testBlocksMulticastIPv6() {
        XCTAssertTrue(SSRGuard.isReservedIPv6("ff02::1"))
    }

    func testAllowsPublicIPv6() {
        XCTAssertFalse(SSRGuard.isReservedIPv6("2001:4860:4860::8888"))
    }

    func testBlocksMetadataHostnames() {
        XCTAssertTrue(SSRGuard.isBlockedHostname("169.254.169.254"))
        XCTAssertTrue(SSRGuard.isBlockedHostname("metadata.google.internal"))
    }

    func testBlocksDotLocal() {
        XCTAssertTrue(SSRGuard.isBlockedHostname("myservice.local"))
        XCTAssertTrue(SSRGuard.isBlockedHostname("db.internal"))
    }

    func testAllowsPublicHostnames() {
        XCTAssertFalse(SSRGuard.isBlockedHostname("google.com"))
        XCTAssertFalse(SSRGuard.isBlockedHostname("api.openai.com"))
    }

    func testCheckSSRFBlocksPrivate() {
        let result = SSRGuard.checkSSRF("http://127.0.0.1:8080/api", allowPrivate: false)
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.errorCode, "SSRF_BLOCKED")
    }

    func testCheckSSRFAllowsWithBypass() {
        let result = SSRGuard.checkSSRF("http://localhost:3000", allowPrivate: true)
        XCTAssertTrue(result.ok)
    }

    func testCheckSSRFAllowsPublicURL() {
        let result = SSRGuard.checkSSRF("https://api.example.com/data", allowPrivate: false)
        XCTAssertTrue(result.ok)
    }

    func testCheckSSRFBlocksFileScheme() {
        let result = SSRGuard.checkSSRF("file:///etc/passwd", allowPrivate: false)
        XCTAssertFalse(result.ok)
    }
}
```

- [ ] **步骤 2: 运行测试验证失败**

```bash
cd Packages/YunPatCore && swift test --filter SSRGuardTests
```
预期: 编译失败 — `SSRGuard` 未定义。

- [ ] **步骤 3: 实现 SSRGuard.swift**

```swift
// Packages/YunPatCore/Sources/YunPatCore/SSR/SSRGuard.swift
import Foundation

/// SSR（Server-Side Request Forgery）防护
/// 防止工具被诱导发送请求到内网/本地/云元数据端点
public enum SSRGuard: Sendable {
    public struct CheckResult: Sendable {
        public let ok: Bool
        public let errorCode: String?
        public let message: String?
    }

    /// 检查 URL 是否应被 SSR 策略阻止
    public static func checkSSRF(_ urlString: String, allowPrivate: Bool) -> CheckResult {
        guard let url = URL(string: urlString) else {
            return CheckResult(ok: false, errorCode: "INVALID_ARGS", message: "Malformed URL")
        }

        // 阻止非 HTTP(S) 方案
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return CheckResult(ok: false, errorCode: "SSRF_BLOCKED",
                               message: "Only http/https schemes allowed; got \(url.scheme ?? "none")")
        }

        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return CheckResult(ok: false, errorCode: "INVALID_ARGS", message: "No host in URL")
        }

        if allowPrivate { return CheckResult(ok: true, errorCode: nil, message: nil) }

        // 阻止内网/保留 IP
        if isPrivateIPv4(host) {
            return CheckResult(ok: false, errorCode: "SSRF_BLOCKED",
                               message: "Private IPv4 address blocked: \(host)")
        }
        if isReservedIPv6(host) {
            return CheckResult(ok: false, errorCode: "SSRF_BLOCKED",
                               message: "Reserved IPv6 address blocked: \(host)")
        }

        // 阻止敏感主机名
        if isBlockedHostname(host) {
            return CheckResult(ok: false, errorCode: "SSRF_BLOCKED",
                               message: "Blocked hostname: \(host)")
        }

        return CheckResult(ok: true, errorCode: nil, message: nil)
    }

    /// 检查是否为私有/保留 IPv4 地址
    /// 涵盖: loopback, RFC1918, link-local, CGNAT, broadcast, documentation, benchmark
    public static func isPrivateIPv4(_ ip: String) -> Bool {
        guard let parts = parseIPv4(ip) else { return false }
        let octets = (parts.0, parts.1, parts.2, parts.3)
        switch octets {
        case (10, _, _, _):                    return true   // RFC1918 Class A
        case (172, 16...31, _, _):             return true   // RFC1918 Class B
        case (192, 168, _, _):                 return true   // RFC1918 Class C
        case (127, _, _, _):                   return true   // Loopback
        case (169, 254, _, _):                 return true   // Link-local
        case (100, 64...127, _, _):            return true   // CGNAT (RFC 6598)
        case (0, _, _, _):                     return true   // "This" network
        case (240..., _, _, _):                return true   // Reserved/Class E
        case (255, 255, 255, 255):             return true   // Broadcast
        default: return false
        }
    }

    /// 检查是否为保留 IPv6 地址
    public static func isReservedIPv6(_ ip: String) -> Bool {
        let lower = ip.lowercased()
        if lower == "::1" { return true }
        if lower.hasPrefix("fe80:") { return true }   // Link-local
        if lower.hasPrefix("fc") || lower.hasPrefix("fd") { return true } // ULA
        if lower.hasPrefix("ff") { return true }        // Multicast
        return false
    }

    /// 检查主机名是否在阻止名单中
    public static func isBlockedHostname(_ host: String) -> Bool {
        let lower = host.lowercased()
        let blocked: Set<String> = [
            "169.254.169.254",          // AWS EC2 metadata
            "metadata.google.internal", // GCP metadata
            "metadata",                  // Azure metadata (via host header)
        ]
        if blocked.contains(lower) { return true }
        if lower.hasSuffix(".local") || lower.hasSuffix(".internal") { return true }
        return false
    }

    private static func parseIPv4(_ ip: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4,
              let a = UInt8(parts[0]), let b = UInt8(parts[1]),
              let c = UInt8(parts[2]), let d = UInt8(parts[3]) else { return nil }
        return (a, b, c, d)
    }
}
```

- [ ] **步骤 4: 运行测试验证通过**

```bash
cd Packages/YunPatCore && swift test --filter SSRGuardTests
```
预期: 14 个测试全部 PASS。

- [ ] **步骤 5: 提交**

```bash
git add Packages/YunPatCore/Sources/YunPatCore/SSR/SSRGuard.swift \
        Tests/YunPatCoreTests/SSRGuardTests.swift
git commit -m "feat: add SSR guard with IPv4/IPv6 double-check and hostname blocklist"
```

---

### 任务 5: 多格式日期解析 (`DateParser`)

**文件:**
- 创建: `Packages/YunPatCore/Sources/YunPatCore/Utils/DateParser.swift`
- 创建: `Tests/YunPatCoreTests/DateParserTests.swift`

**步骤:**

- [ ] **步骤 1: 编写 DateParser 测试**

```swift
// Tests/YunPatCoreTests/DateParserTests.swift
import XCTest
@testable import YunPatCore

final class DateParserTests: XCTestCase {
    func testISO8601WithFractional() throws {
        let d = try DateParser.parse("2024-03-15T10:30:00.123Z")
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: d)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
    }

    func testISO8601WithoutFractional() throws {
        let d = try DateParser.parse("2024-12-01T08:00:00Z")
        XCTAssertNotNil(d)
    }

    func testDateOnly() throws {
        let d = try DateParser.parse("2024-01-31")
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: d)
        XCTAssertEqual(comps.day, 31)
    }

    func testRFC2822() throws {
        let d = try DateParser.parse("Mon, 15 Mar 2024 10:30:00 +0800")
        XCTAssertNotNil(d)
    }

    func testUnixSeconds() throws {
        let d = try DateParser.parse("1710499200")
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: d)
        XCTAssertEqual(comps.year, 2024)
    }

    func testUnixMilliseconds() throws {
        let d = try DateParser.parse("1710499200000")
        XCTAssertNotNil(d)
    }

    func testChineseDateFormat() throws {
        let d = try DateParser.parse("2024年3月15日")
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: d)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
    }

    func testCNIPADateFormat() throws {
        let d = try DateParser.parse("2024.03.15")
        XCTAssertNotNil(d)
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try DateParser.parse("not a date at all"))
    }

    func testISODuration() throws {
        let secs = try DateParser.parseISODuration("P3DT2H30M")
        XCTAssertEqual(secs, 3 * 86400 + 2 * 3600 + 30 * 60)
    }

    func testISODurationNegative() throws {
        let secs = try DateParser.parseISODuration("-P1D")
        XCTAssertEqual(secs, -86400)
    }

    func testISODurationEmptyThrows() {
        XCTAssertThrowsError(try DateParser.parseISODuration("P"))
    }
}
```

- [ ] **步骤 2: 运行测试验证失败**

```bash
cd Packages/YunPatCore && swift test --filter DateParserTests
```
预期: 编译失败 — `DateParser` 未定义。

- [ ] **步骤 3: 实现 DateParser.swift**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Utils/DateParser.swift
import Foundation

/// 多格式日期解析器 — 对齐 Osaurus time 工具
/// 支持 ISO 8601、RFC 2822、yyyy-MM-dd、中文日期、Unix 时间戳等
public enum DateParser: Sendable {
    public enum ParseError: Error {
        case unrecognizedFormat(String)
        case invalidDuration(String)
    }

    private static let iso8601Full: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601NoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let rfc2822Formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let chineseFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    private static let dotFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public static func parse(_ input: String) throws -> Date {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. ISO 8601 with fractional seconds
        if let d = iso8601Full.date(from: trimmed) { return d }
        // 2. ISO 8601 without fractional
        if let d = iso8601NoFrac.date(from: trimmed) { return d }
        // 3. Date-only
        if let d = dateOnlyFormatter.date(from: trimmed) { return d }
        // 4. RFC 2822
        if let d = rfc2822Formatter.date(from: trimmed) { return d }
        // 5. Chinese date
        if let d = chineseFormatter.date(from: trimmed) { return d }
        // 6. Dot format (CNIPA style)
        if let d = dotFormatter.date(from: trimmed) { return d }
        // 7. Unix seconds (10 digits, year 2001-2286)
        if let ts = Double(trimmed), trimmed.count == 10, ts > 978307200, ts < 9999999999 {
            return Date(timeIntervalSince1970: ts)
        }
        // 8. Unix milliseconds (13 digits)
        if let ts = Double(trimmed), trimmed.count == 13, ts > 978307200000, ts < 9999999999999 {
            return Date(timeIntervalSince1970: ts / 1000.0)
        }

        throw ParseError.unrecognizedFormat(trimmed)
    }

    /// 解析 ISO 8601 Duration (e.g. P3DT2H30M, PT90M, -P1D)
    public static func parseISODuration(_ input: String) throws -> TimeInterval {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var negative = false
        var remaining = trimmed
        if remaining.hasPrefix("-") {
            negative = true
            remaining = String(remaining.dropFirst())
        }

        guard remaining.hasPrefix("P") else { throw ParseError.invalidDuration(trimmed) }
        remaining = String(remaining.dropFirst())

        var seconds: TimeInterval = 0
        var current = ""
        var inTime = false

        for ch in remaining {
            if ch == "T" { inTime = true; continue }
            if ch.isNumber || ch == "." {
                current.append(ch)
            } else {
                guard let val = Double(current) else { throw ParseError.invalidDuration(trimmed) }
                switch ch {
                case "Y": seconds += val * 365.25 * 86400
                case "M": seconds += val * (inTime ? 60 : 30.4375 * 86400)
                case "W": seconds += val * 7 * 86400
                case "D": seconds += val * 86400
                case "H": seconds += val * 3600
                case "S": seconds += val
                default: throw ParseError.invalidDuration(trimmed)
                }
                current = ""
            }
        }

        if !current.isEmpty { throw ParseError.invalidDuration(trimmed) }
        if seconds == 0 && !negative { throw ParseError.invalidDuration(trimmed) }

        return negative ? -seconds : seconds
    }
}
```

- [ ] **步骤 4: 运行测试验证通过**

```bash
cd Packages/YunPatCore && swift test --filter DateParserTests
```
预期: 12 个测试全部 PASS。

- [ ] **步骤 5: 提交**

```bash
git add Packages/YunPatCore/Sources/YunPatCore/Utils/DateParser.swift \
        Tests/YunPatCoreTests/DateParserTests.swift
git commit -m "feat: add multi-format date parser with ISO 8601/RFC 2822/Chinese/Unix support"
```

---

## 第二部分：工程基础设施（P1）

### 任务 6: CI 工具注册校验脚本

**文件:**
- 创建: `scripts/validate-tools.swift`

**步骤:**

- [ ] **步骤 1: 编写 CI 校验脚本**

```swift
#!/usr/bin/env swift
import Foundation

// MARK: - Validation Rules
let requiredHandlerPrefixes: Set<String> = ["handle", "todo", "complete", "clarify"]
let bannedSummaryWords: Set<String> = ["done", "ok", "完成", "已完成", "好了", "complete", "finished"]

// MARK: - Scan ToolDispatch.swift for registered tools
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let toolDispatchPath = repoRoot
    .appendingPathComponent("Packages/YunPatCore/Sources/YunPatCore/Loop/ToolDispatch.swift")

guard FileManager.default.fileExists(atPath: toolDispatchPath.path) else {
    print("ERROR: ToolDispatch.swift not found at \(toolDispatchPath.path)")
    exit(2)
}

let source = try String(contentsOf: toolDispatchPath, encoding: .utf8)
var errors: [String] = []
var warnings: [String] = []

// 1. Extract registered tool names from buildDispatchTable()
let handlerPattern = try! NSRegularExpression(
    pattern: #"handlers\["([^"]+)"\]\s*="# , options: []
)
let toolNames = handlerPattern.matches(in: source, range: NSRange(source.startIndex..., in: source))
    .compactMap { match -> String? in
        guard let r = Range(match.range(at: 1), in: source) else { return nil }
        let name = String(source[r])
        // Skip aliases (task_complete → complete, ask_user → clarify)
        if name == "task_complete" || name == "ask_user" { return nil }
        return name
    }

if toolNames.isEmpty {
    errors.append("No tools registered in buildDispatchTable()")
} else {
    print("Found \(toolNames.count) unique tools: \(toolNames.sorted().joined(separator: ", "))")
}

// 2. Check for duplicate registrations
let duplicates = Dictionary(grouping: toolNames, by: { $0 }).filter { $0.value.count > 1 }
for (name, _) in duplicates {
    errors.append("Duplicate registration: \(name)")
}

// 3. Check that every tool has a TOOL.md
let docsDir = repoRoot
    .appendingPathComponent("Packages/YunPatCore/Sources/YunPatCore/Tools/Docs")
for name in toolNames {
    let docPath = docsDir.appendingPathComponent("\(name).md")
    if !FileManager.default.fileExists(atPath: docPath.path) {
        warnings.append("Missing TOOL.md for: \(name) — expected at \(docPath.path)")
    }
}

// 4. Check readOnlyTools consistency
let readOnlyPattern = try! NSRegularExpression(
    pattern: #"readOnlyTools: Set<String> = \[([^\]]+)\]"# , options: [.dotMatchesLineSeparators]
)
if let match = readOnlyPattern.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
   let r = Range(match.range(at: 1), in: source) {
    let body = String(source[r])
    let readOnlyNames = body
        .components(separatedBy: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "") }
        .filter { !$0.isEmpty && !$0.hasPrefix("//") }

    for roName in readOnlyNames {
        if !toolNames.contains(roName) && roName != "read_dir" &&
           !roName.hasPrefix("git_") && !roName.hasPrefix("ax_") {
            warnings.append("readOnly tool '\(roName)' not found in dispatch table")
        }
    }
}

// 5. Report
if errors.isEmpty && warnings.isEmpty {
    print("✅ All tool validations passed.")
    exit(0)
}

if !warnings.isEmpty {
    print("\n⚠️  WARNINGS:")
    for w in warnings { print("  - \(w)") }
}
if !errors.isEmpty {
    print("\n❌ ERRORS:")
    for e in errors { print("  - \(e)") }
    exit(1)
}
exit(0)
```

- [ ] **步骤 2: 运行校验脚本确认通过**

```bash
swift scripts/validate-tools.swift
```
预期: `✅ All tool validations passed.` （或 `⚠️  WARNINGS: Missing TOOL.md for: ...` — 在全部 TOOL.md 编写前允许 warnings，但不可 errors）

- [ ] **步骤 3: 添加 GitHub Actions CI step**

在 `.github/workflows/` 下的 CI 配置中添加：

```yaml
- name: Validate Tool Registry
  run: swift scripts/validate-tools.swift
```

- [ ] **步骤 4: 提交**

```bash
git add scripts/validate-tools.swift .github/workflows/ci.yml
git commit -m "ci: add tool registry validation script with TOOL.md and dedup checks"
```

---

### 任务 7: 声明式 Secrets 配置

**文件:**
- 创建: `Packages/YunPatPlugins/Sources/YunPatPlugins/PluginSecrets.swift`
- 修改: `Packages/YunPatPlugins/Sources/YunPatPlugins/PluginTypes.swift`

**步骤:**

- [ ] **步骤 1: 编写测试**

```swift
// Tests/YunPatPluginsTests/PluginSecretsTests.swift
import XCTest
@testable import YunPatPlugins

final class PluginSecretsTests: XCTestCase {
    func testSecretDefinition() {
        let secret = PluginSecret(id: "api_key", label: "API Key",
                                   description: "Get from [Portal](https://example.com)",
                                   required: true, url: "https://example.com/api")
        XCTAssertTrue(secret.required)
        XCTAssertEqual(secret.id, "api_key")
    }

    func testManifestWithSecrets() {
        let secret = PluginSecret(id: "key", label: "Key", required: true)
        let manifest = PluginManifest(id: "test.tool", name: "Test", version: "1.0",
                                       level: .tool, description: "", author: "",
                                       permissions: [], secrets: [secret])
        XCTAssertEqual(manifest.secrets?.count, 1)
    }

    func testOptionalSecret() {
        let secret = PluginSecret(id: "backup", label: "Backup Key", required: false)
        XCTAssertFalse(secret.required)
    }
}
```

- [ ] **步骤 2: 实现 PluginSecrets.swift**

```swift
// Packages/YunPatPlugins/Sources/YunPatPlugins/PluginSecrets.swift
import Foundation

/// 声明式插件 secret 配置 — 对齐 Osaurus secrets schema
public struct PluginSecret: Codable, Sendable {
    public let id: String
    public let label: String
    public let description: String?
    public let required: Bool
    public let url: String?

    public init(id: String, label: String, description: String? = nil,
                required: Bool = true, url: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
        self.required = required
        self.url = url
    }
}
```

- [ ] **步骤 3: 扩展 PluginManifest 增加 secrets/sha256/signature 字段**

```swift
// 在 PluginTypes.swift 中修改 PluginManifest
public struct PluginManifest: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let minAppVersion: String
    public let level: PluginLevel
    public let description: String
    public let author: String
    public let permissions: [PluginPermission]
    // 新增
    public let secrets: [PluginSecret]?       // 声明式 API key 需求
    public let sha256: String?                // 包校验和
    public let signature: String?             // 数字签名

    public init(id: String, name: String, version: String,
                minAppVersion: String = "1.0.0", level: PluginLevel = .tool,
                description: String = "", author: String = "",
                permissions: [PluginPermission] = [],
                secrets: [PluginSecret]? = nil,
                sha256: String? = nil, signature: String? = nil) {
        self.id = id; self.name = name; self.version = version
        self.minAppVersion = minAppVersion; self.level = level
        self.description = description; self.author = author
        self.permissions = permissions
        self.secrets = secrets
        self.sha256 = sha256
        self.signature = signature
    }
}
```

- [ ] **步骤 4: 运行测试验证通过**

```bash
cd Packages/YunPatPlugins && swift test --filter PluginSecretsTests
```
预期: 3 个测试 PASS。

- [ ] **步骤 5: 提交**

```bash
git add Packages/YunPatPlugins/Sources/YunPatPlugins/PluginSecrets.swift \
        Packages/YunPatPlugins/Sources/YunPatPlugins/PluginTypes.swift \
        Tests/YunPatPluginsTests/PluginSecretsTests.swift
git commit -m "feat: add declarative plugin secrets config with sha256/signature manifest fields"
```

---

### 任务 8: 注册表自动同步脚本

**文件:**
- 创建: `scripts/sync-plugin-registry.swift`

**步骤:**

- [ ] **步骤 1: 编写同步脚本**

```swift
#!/usr/bin/env swift
import Foundation

/// 自动同步工具代码定义到注册表 JSON
/// 用法:
///   swift scripts/sync-plugin-registry.swift              # 同步
///   swift scripts/sync-plugin-registry.swift --check       # CI 检测漂移
///
/// 把 ToolDispatch.swift 中注册的工具名与 plugins/registry.json 中声明对比，
/// 检测漂移：新增未注册的工具、注册表中已删除的工具。

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let checkOnly = CommandLine.arguments.contains("--check")

// 1. 从 ToolDispatch.swift 提取注册的工具
let dispatchPath = repoRoot
    .appendingPathComponent("Packages/YunPatCore/Sources/YunPatCore/Loop/ToolDispatch.swift")
let source = try String(contentsOf: dispatchPath, encoding: .utf8)

let handlerPattern = try! NSRegularExpression(
    pattern: #"handlers\["([^"]+)"\]\s*="# , options: []
)
let codeTools = Set(handlerPattern.matches(in: source, range: NSRange(source.startIndex..., in: source))
    .compactMap { match -> String? in
        guard let r = Range(match.range(at: 1), in: source) else { return nil }
        let name = String(source[r])
        return (name == "task_complete" || name == "ask_user") ? nil : name
    })

// 2. 读取 registry.json（如存在）
let registryPath = repoRoot.appendingPathComponent("plugins/registry.json")
var registryTools = Set<String>()
if FileManager.default.fileExists(atPath: registryPath.path) {
    let data = try Data(contentsOf: registryPath)
    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
       let tools = json["tools"] as? [[String: Any]] {
        registryTools = Set(tools.compactMap { $0["name"] as? String })
    }
}

// 3. 检测漂移
let added = codeTools.subtracting(registryTools)
let removed = registryTools.subtracting(codeTools)

if added.isEmpty && removed.isEmpty {
    print("✅ Registry in sync — \(codeTools.count) tools.")
    exit(0)
}

if !added.isEmpty {
    print("➕ Tools in code but NOT in registry: \(added.sorted().joined(separator: ", "))")
}
if !removed.isEmpty {
    print("➖ Tools in registry but NOT in code: \(removed.sorted().joined(separator: ", "))")
}

if checkOnly {
    print("\n❌ Registry drift detected. Run 'swift scripts/sync-plugin-registry.swift' to sync.")
    exit(1)
}

// 4. 生成新的 registry.json
let toolEntries = codeTools.sorted().map { name -> [String: Any] in
    ["name": name, "source": "builtin", "version": "1.0.0"]
}
let registry: [String: Any] = [
    "generated": ISO8601DateFormatter().string(from: Date()),
    "toolCount": toolEntries.count,
    "tools": toolEntries,
]
let jsonData = try JSONSerialization.data(withJSONObject: registry, options: [.prettyPrinted, .sortedKeys])
let registryDir = registryPath.deletingLastPathComponent()
try FileManager.default.createDirectory(at: registryDir, withIntermediateDirectories: true)
try jsonData.write(to: registryPath)
print("✅ Registry written — \(codeTools.count) tools → \(registryPath.path)")
exit(0)
```

- [ ] **步骤 2: 运行同步并确认**

```bash
swift scripts/sync-plugin-registry.swift
```
预期: `✅ Registry written — N tools → plugins/registry.json`

- [ ] **步骤 3: 运行 --check 模式**

```bash
swift scripts/sync-plugin-registry.swift --check
```
预期: `✅ Registry in sync — N tools.`

- [ ] **步骤 4: 提交**

```bash
git add scripts/sync-plugin-registry.swift plugins/registry.json
git commit -m "feat: add plugin registry auto-sync script with drift detection"
```

---

## 验收检查清单

### P0 — 核心工程体系

- [ ] `ToolResponse` 信封定义存在，含 `ok`/`data`/`error`/`warnings` 字段
- [ ] `ToolErrorCode` 枚举含 15+ 结构化错误码
- [ ] `ToolEnvelope` 向后兼容扩展（旧 init 仍可用，新增 `errorCode`/`errorHint`/`warnings`）
- [ ] `ToolDispatch.executeCall` 自动识别 ToolResponse JSON 并解析
- [ ] `handleWriteFile` 返回 ToolResponse JSON 而非散文本
- [ ] 12 个工具的 `TOOL.md` 全部就位
- [ ] `ToolDefinition` 含 `usageGuide` 字段
- [ ] `CapabilityRegistry.usageGuide(for:)` 方法加载 TOOL.md
- [ ] `ContextEngine.buildPrompt` 含工具使用指南块
- [ ] `SSRGuard` 含 IPv4/IPv6 双重检测 + 主机名阻止名单
- [ ] `DateParser` 支持 8 种日期格式 + ISO Duration
- [ ] 所有现有测试无回归
- [ ] 新增测试文件 ≥5 个，测试用例 ≥40 个

### P1 — 工程基础设施

- [ ] `scripts/validate-tools.swift` CI 校验脚本，检测重复注册/缺失 TOOL.md/readOnly 不一致
- [ ] `PluginSecret` 声明式 secrets 类型
- [ ] `PluginManifest` 含 `secrets`/`sha256`/`signature` 字段
- [ ] `scripts/sync-plugin-registry.swift` 同步脚本，含 `--check` CI 模式
- [ ] `plugins/registry.json` 自动生成

---

## 整体执行策略

### 阶段 A：核心信封（任务 1 + 6）

先落地 `ToolResponse` + 校验脚本，确保后续任务有标准化的输入输出契约可用。

- [ ] 任务 1: ToolResponse 信封
- [ ] 任务 6: CI 校验脚本
- [ ] 检查点: 所有现有测试通过 + CI 校验通过

### 阶段 B：工具指导 + 能力扩展（任务 2 + 3 + 4 + 5）

在标准化信封之上，添加安全层和易用性层。

- [ ] 任务 2: Per-tool TOOL.md
- [ ] 任务 3: ToolDefinition + CapabilityRegistry 加载
- [ ] 任务 4: SSR 防护
- [ ] 任务 5: 日期解析
- [ ] 检查点: 所有新增测试通过 + 工具指导生效

### 阶段 C：工程基础设施（任务 7 + 8）

- [ ] 任务 7: 声明式 Secrets
- [ ] 任务 8: 注册表同步
- [ ] 检查点: 全量测试通过 + registry.json 无漂移

---

## 风险与回退

| 风险 | 缓解 |
|---|---|
| `ToolResponse` 改动面大，影响所有工具 handler | 向后兼容：旧 `.handled(String)` 仍可用，新工具逐步迁移 |
| TOOL.md 内容长，可能增加 system prompt token 消耗 | 只拼前 15 行摘要（~300 tokens），非全量注入 |
| `#filePath` 在 CapabilityRegistry 中依赖源码路径 | 生产构建时回退到 Bundle.module 查找 |
| `DateParser` 中文字符处理与 Foundation 版本相关 | 优先 ISO 8601；中文格式回退链在最末 |
