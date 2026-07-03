import CoreGraphics
import Foundation
import YunPatNetworking

// MARK: - Tool Dispatch Types

/// 工具执行上下文 — 传递当前工具 ID、项目目录和选中的模型提供商
public struct ToolContext: Sendable {
    public let toolId: String
    public let projectFolder: String
    public let selectedProvider: ModelProvider

    public init(toolId: String, projectFolder: String, selectedProvider: ModelProvider) {
        self.toolId = toolId
        self.projectFolder = projectFolder
        self.selectedProvider = selectedProvider
    }
}

/// 工具处理器返回值 — handled / alreadyAppended / notHandled / taskComplete 四种分派结果
public enum ToolHandlerResult: Sendable {
    /// 工具已处理，返回结果文本
    case handled(String)
    /// 工具已处理，结果已追加到 toolResults（如 MCP 工具直接追加）
    case alreadyAppended
    /// 工具未被此处理器识别
    case notHandled
    /// 任务完成，停止执行
    case taskComplete(String)
}

/// 工具处理器函数签名 — (name: 工具名, input: 参数字典, context: 执行上下文) async → ToolHandlerResult
public typealias ToolHandler = @Sendable (String, [String: JSONValue], ToolContext) async -> ToolHandlerResult

// MARK: - Tool Dispatch Table

/// 工具分派表: O(1) 字典查找 + 运行时注册
///
/// 设计参考 Agent-main (macOS26/Agent) 的 dispatchTable 模式:
/// - 字典派发，避免 if-else 链
/// - 运行时 registerToolHandler 支持插件/MCP 动态注册
/// - readOnlyTools 集合标记安全工具，用于并行批处理
public final class ToolDispatch: @unchecked Sendable {
    public static let shared: ToolDispatch = ToolDispatch()

    private let searchCommanderLock = NSLock()
    private var _searchCommander: SearchCommander?

    public func configure(searchCommander: SearchCommander) {
        searchCommanderLock.lock()
        _searchCommander = searchCommander
        searchCommanderLock.unlock()
    }

    public var searchCommander: SearchCommander? {
        searchCommanderLock.lock()
        defer { searchCommanderLock.unlock() }
        return _searchCommander
    }

    private let lock: NSLock = NSLock()
    var handlers: [String: ToolHandler] = [:]
    var toolSpecs: [String: ToolSpec] = [:]

    private let todoChecklistLock: NSLock = NSLock()
    private var _todoChecklist: String = ""

    var todoChecklist: String {
        get { todoChecklistLock.withLock { _todoChecklist } }
        set { todoChecklistLock.withLock { _todoChecklist = newValue } }
    }

    private init() {
        buildDispatchTable()
    }
}

// MARK: - Registration & Lookup

extension ToolDispatch {

    /// 运行时注册一个工具处理器（供 MCP/Plugin 使用）
    public func register(name: String, description: String = "", handler: @escaping ToolHandler) {
        lock.lock()
        defer { lock.unlock() }
        handlers[name] = handler
        toolSpecs[name] = ToolSpec(name: name, description: description)
    }

    /// 注销工具处理器
    public func unregister(name: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: name)
    }

    /// 查找处理器，O(1)
    public func handler(for name: String) -> ToolHandler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[name]
    }

    /// 已注册的所有工具名
    public var registeredTools: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(handlers.keys)
    }

    /// 所有工具的描述（供 PatentToolLoop 使用）
    public var allToolSpecs: [ToolSpec] {
        lock.lock()
        defer { lock.unlock() }
        return Array(toolSpecs.values)
    }
}

// MARK: - Read-Only Tool Detection

extension ToolDispatch {

    /// 只读工具集合 — 无文件写入、无 UI 操作、无状态变更
    /// 这些工具可以安全地在 TaskGroup 中并行预执行
    public static let readOnlyTools: Set<String> = [
        // 文件读取
        "list_files", "search_files", "read_dir", "read_file",
        // Git 读取
        "git_status", "git_diff", "git_log",
        // 桌面读取
        "ax_list_windows", "ax_get_properties", "ax_find_element",
        "ax_get_focused_element", "ax_read_focused", "ax_screenshot",
        // 工具获取
        "list_tools",
        // 专利检索 (只读查询)
        "patent_search", "legal_status_query",
        // 知识库检索 (只读查询)
        "knowledge_search"
    ]

    /// 判断工具是否为只读
    public func isReadOnly(name: String) -> Bool {
        Self.readOnlyTools.contains(name)
    }
}

// MARK: - ListToolsTool (保留在核心因为 list_tools 是基础工具)

/// 列出所有可用的工具
private struct ListToolsTool: TypedTool {
    let name: String = "list_tools"
    let description: String = "列出所有可用的工具及其简要描述。"

    struct Args: Decodable, Sendable {}

    func execute(input: Args, context: ToolContext) async throws -> ToolResponse {
        let tools: [String] = ToolDispatch.shared.registeredTools.sorted()
        let list: String = tools.joined(separator: "\n- ")
        return ToolResponse.okResp(data: .string("【可用工具】\n- \(list)"))
    }
}

// MARK: - 核心分派入口 & Loop 工具

extension ToolDispatch {

    /// 桥接 PatentToolLoop 的 ToolCall → ToolDispatch → ToolEnvelope
    public static func executeCall(_ call: ToolCall, ctx: ToolContext) async -> ToolEnvelope {
        let input: [String: JSONValue] = call.arguments.reduce(into: [String: JSONValue]()) { result, entry in
            result[entry.key] = .string(entry.value)
        }
        let result: ToolHandlerResult = await shared.dispatchWithHooks(name: call.name, input: input, ctx: ctx)
        switch result {
        case .handled(let text):
            if let response: ToolResponse = ToolResponse.tryParse(text) {
                return ToolEnvelope(from: response, toolName: call.name)
            }
            return ToolEnvelope(toolName: call.name, content: text)
        case .taskComplete(let summary):
            return ToolEnvelope(toolName: call.name, content: summary)
        case .alreadyAppended:
            return ToolEnvelope(toolName: call.name, content: "processed")
        case .notHandled:
            return ToolEnvelope(
                toolName: call.name, content: "Unknown tool: \(call.name)",
                isError: true, errorCode: ToolErrorCode.unknownTool.rawValue
            )
        }
    }

    /// 构建内置工具分派表
    private func buildDispatchTable() {
        registerLoopTools()
        registerFileTools()
        registerAXorcistTools()
        registerPatentTools()
        registerDocTools()
    }

    private func registerLoopTools() {
        let listTools: ListToolsTool = ListToolsTool()
        handlers[listTools.name] = listTools.handler
        toolSpecs[listTools.name] = ToolSpec(name: listTools.name, description: listTools.description)

        handlers["todo"] = { name, input, context in
            await Self.handleTodo(name: name, input: input, ctx: context)
        }
        toolSpecs["todo"] = ToolSpec(
            name: "todo",
            description: "写入或替换任务检查清单。每次调用替换整个清单。使用 Markdown 格式，待办项以 `- [ ]` 开头，已完成项以 `- [x]` 开头。"
        )
        handlers["complete"] = { name, input, context in
            await Self.handleComplete(name: name, input: input, ctx: context)
        }
        toolSpecs["complete"] = ToolSpec(
            name: "complete",
            description: "结束当前任务并提供一个已验证的总结摘要。摘要必须 ≥30 个字符且有意义的描述实际操作内容，拒绝占位符。"
        )
        handlers["task_complete"] = handlers["complete"]
        handlers["clarify"] = { name, input, context in
            await Self.handleClarify(name: name, input: input, ctx: context)
        }
        toolSpecs["clarify"] = ToolSpec(
            name: "clarify",
            description: "暂停任务并询问一个关键问题。提供 options 限制回答范围。仅用于真正阻塞性的歧义，小问题自行做出合理默认选择。"
        )
        handlers["ask_user"] = handlers["clarify"]
    }

    // MARK: - Loop Tools (todo / complete / clarify)

    private static func handleTodo(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let markdown: String = input["markdown"]?.stringValue ?? ""
        guard !markdown.isEmpty else { return .handled("Error: markdown field required") }
        shared.todoChecklist = markdown
        return .handled("✅ 任务清单已更新:\n\n\(markdown)")
    }

    private static func handleComplete(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let summary: String = input["summary"]?.stringValue ?? ""
        guard AgentLoopTools.validate(summary: summary) else {
            return .handled(
                "Error: summary must be ≥30 characters of meaningful prose. "
                    + "Placeholders like 'done', 'ok', '已完成' are rejected. "
                    + "Describe what you did and how you verified."
            )
        }
        return .taskComplete(summary)
    }

    private static func handleClarify(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let question: String = input["question"]?.stringValue ?? ""
        let options: [String] = (input["options"]?.arrayValue ?? []).compactMap { $0.stringValue }
        let allowMultiple: Bool = input["allow_multiple"]?.boolValue ?? false
        guard !question.isEmpty else { return .handled("Error: question field required") }
        var result: String = "⚠️ 需要用户确认: \(question)"
        if !options.isEmpty {
            let opts: String = options.prefix(6).enumerated().map { index, option in
                "  \(index + 1). \(option)"
            }.joined(separator: "\n")
            result += "\n\n选项:\n\(opts)"
        }
        if allowMultiple { result += "\n(可多选)" }
        return .handled(result)
    }

    // MARK: - Dispatch with Hooks

    /// 带 Hooks 分派: 先执行 preToolUse hooks (可 block)，再执行工具，最后 postToolUse hooks
    public func dispatchWithHooks(
        name: String,
        input: [String: JSONValue],
        ctx: ToolContext
    ) async -> ToolHandlerResult {
        let (decision, hookMessage): (HookDecision, String?) = await HooksService.shared
            .runPreToolHooks(toolName: name, input: ToolInput(input))
        if decision == .block {
            let message: String = hookMessage ?? "Blocked by hook"
            return .handled(message)
        }

        guard let handler: ToolHandler = handler(for: name) else {
            return .notHandled
        }
        let result: ToolHandlerResult = await handler(name, input, ctx)

        if case .handled(let output) = result {
            if let transformed = await HooksService.shared.runPostToolHooks(
                toolName: name, input: ToolInput(input), output: output
            ) {
                return .handled(transformed)
            }
        }

        return result
    }
}
