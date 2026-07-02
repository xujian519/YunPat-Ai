import CoreGraphics
import Foundation
import YunPatNetworking

// swiftlint:disable file_length

// MARK: - Tool Dispatch Types

/// 传递给每个工具处理器的统一上下文
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

/// 工具处理器返回值
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

/// 工具处理器函数签名
public typealias ToolHandler = @Sendable (String, [String: Any], ToolContext) async -> ToolHandlerResult

// MARK: - Tool Dispatch Table

/// 工具分派表: O(1) 字典查找 + 运行时注册
///
/// 设计参考 Agent-main (macOS26/Agent) 的 dispatchTable 模式:
/// - 字典派发，避免 if-else 链
/// - 运行时 registerToolHandler 支持插件/MCP 动态注册
/// - readOnlyTools 集合标记安全工具，用于并行批处理
public final class ToolDispatch: @unchecked Sendable {
    public static let shared: ToolDispatch = ToolDispatch()

    private nonisolated(unsafe) static var _searchCommander: SearchCommander?

    public func configure(searchCommander: SearchCommander) {
        Self._searchCommander = searchCommander
    }

    public var searchCommander: SearchCommander? {
        Self._searchCommander
    }

    private let lock: NSLock = NSLock()
    private var handlers: [String: ToolHandler] = [:]
    /// 工具描述（供 PatentToolLoop.registeredTools 使用）
    private var toolSpecs: [String: ToolSpec] = [:]

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

// MARK: - TypedTool 实现（桥接到 TypedTool 协议的工具）

/// 列出所有可用的工具
private struct ListToolsTool: TypedTool {
    let name: String = "list_tools"
    let description: String = "列出所有可用的工具及其简要描述。"

    struct Args: Decodable, Sendable {
        // list_tools 无需参数
    }

    func execute(input: Args, context: ToolContext) async throws -> ToolResponse {
        let tools: [String] = ToolDispatch.shared.registeredTools.sorted()
        let list: String = tools.joined(separator: "\n- ")
        return ToolResponse.okResp(data: .string("【可用工具】\n- \(list)"))
    }
}

/// 获取 PDF 元数据
private struct GetPDFInfoTool: TypedTool {
    let name: String = "pdf_get_info"
    let description: String = "获取 PDF 文件的元数据：页数、尺寸、加密状态。先调用此工具了解 PDF 总页数，再使用 pdf_render_page 渲染指定页。"

    struct Args: Decodable, Sendable {
        let pdf_path: String
        let _context_folder: String?
    }

    func execute(input: Args, context: ToolContext) async throws -> ToolResponse {
        let folder: String = input._context_folder ?? context.projectFolder
        guard !folder.isEmpty else {
            return ToolResponse.errResp(code: .invalidArgs, message: "pdf_path 是必填参数")
        }
        do {
            let contextFolder: String? = folder.isEmpty ? nil : folder
            let info: PDFRenderer.PageInfo = try PDFRenderer.getInfo(
                from: input.pdf_path, contextFolder: contextFolder
            )
            let encoder: JSONEncoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data: Data = try? encoder.encode(info),
                let dict: [String: Any] = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return ToolResponse.errResp(code: .internalError, message: "JSON 编码失败")
            }
            let jsonData: Data = try JSONSerialization.data(withJSONObject: dict)
            let jsonValue: JSONValue = try JSONDecoder().decode(JSONValue.self, from: jsonData)
            return ToolResponse.okResp(data: jsonValue)
        } catch {
            return ToolResponse.errResp(code: .readError, message: error.localizedDescription)
        }
    }
}

/// 渲染 PDF 页面为图像（供 OCR/文档检测使用）
private struct RenderPDFPageTool: TypedTool {
    let name: String = "pdf_render_page"
    let description: String = "渲染 PDF 指定页为图像。与 detect_text / detect_document 配合使用。返回渲染后的图像临时路径。"

    struct Args: Decodable, Sendable {
        let pdf_path: String
        let page: Int?
        let dpi: Int?
        let output_path: String?
        let _context_folder: String?
    }

    func execute(input: Args, context: ToolContext) async throws -> ToolResponse {
        let folder: String = input._context_folder ?? context.projectFolder
        let page: Int = input.page ?? 1
        let dpi: Int = input.dpi ?? 300

        do {
            let cgImage: CGImage = try PDFRenderer.renderPage(
                from: input.pdf_path,
                contextFolder: folder.isEmpty ? nil : folder,
                page: page,
                dpi: dpi
            )

            // 渲染成功但当前不保存图像，仅返回 CGImage 元数据
            let result: [String: JSONValue] = [
                "page": .number(Double(page)),
                "dpi": .number(Double(dpi)),
                "width": .number(Double(cgImage.width)),
                "height": .number(Double(cgImage.height)),
                "status": .string("rendered")
            ]
            return ToolResponse.okResp(data: .object(result))
        } catch {
            return ToolResponse.errResp(code: .readError, message: error.localizedDescription)
        }
    }
}

// MARK: - Built-in Dispatch Table

extension ToolDispatch {

    /// 桥接 PatentToolLoop 的 ToolCall → ToolDispatch → ToolEnvelope
    public static func executeCall(_ call: ToolCall, ctx: ToolContext) async -> ToolEnvelope {
        let input: [String: Any] = call.arguments.reduce(into: [String: Any]()) { $0[$1.key] = $1.value }
        let result: ToolHandlerResult = await shared.dispatchWithHooks(name: call.name, input: input, ctx: ctx)
        switch result {
        case .handled(let text):
            // 尝试解析为 ToolResponse JSON，新工具返回标准化信封
            if let response: ToolResponse = ToolResponse.tryParse(text) {
                return ToolEnvelope(from: response, toolName: call.name)
            }
            // 旧工具返回散文本路径
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

    // swiftlint:disable:next function_body_length
    /// 构建内置工具分派表
    private func buildDispatchTable() {
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
        handlers["read_file"] = { name, input, context in
            await Self.handleReadFile(name: name, input: input, ctx: context)
        }
        toolSpecs["read_file"] = ToolSpec(
            name: "read_file",
            description: "读取文件内容（支持行范围指定）或列出目录内容。"
        )
        handlers["write_file"] = { name, input, context in
            await Self.handleWriteFile(name: name, input: input, ctx: context)
        }
        toolSpecs["write_file"] = ToolSpec(
            name: "write_file",
            description: "创建或覆写文件。使用 dry_run: true 预览变更而不实际写入。"
        )
        handlers["list_files"] = { name, input, context in
            await Self.handleListFiles(name: name, input: input, ctx: context)
        }
        toolSpecs["list_files"] = ToolSpec(
            name: "list_files",
            description: "按 glob 模式列出工作目录中的文件。"
        )
        handlers["search_files"] = { name, input, context in
            await Self.handleSearchFiles(name: name, input: input, ctx: context)
        }
        toolSpecs["search_files"] = ToolSpec(
            name: "search_files",
            description: "对文件内容进行 ripgrep 风格搜索。"
        )
        handlers["execute_shell"] = { name, input, context in
            await Self.handleExecuteShell(name: name, input: input, ctx: context)
        }
        toolSpecs["execute_shell"] = ToolSpec(
            name: "execute_shell",
            description: "执行一个 shell 命令。需要用户批准。"
        )
        handlers["patent_search"] = { name, input, context in
            await Self.handlePatentSearch(name: name, input: input, ctx: context)
        }
        toolSpecs["patent_search"] = ToolSpec(
            name: "patent_search",
            description: "在 Google Patents / CNIPA 检索专利文献。传入布尔检索式或关键词。"
        )
        handlers["legal_status_query"] = { name, input, context in
            await Self.handleLegalStatusQuery(name: name, input: input, ctx: context)
        }
        toolSpecs["legal_status_query"] = ToolSpec(
            name: "legal_status_query",
            description: "查询专利的法律状态。传入专利公开号。"
        )
        handlers["knowledge_search"] = { name, input, context in
            await Self.handleKnowledgeSearch(name: name, input: input, ctx: context)
        }
        toolSpecs["knowledge_search"] = ToolSpec(
            name: "knowledge_search",
            description: "在宝宸知识库中检索专利法规、审查指南和判例。"
        )

        let pdfInfo: GetPDFInfoTool = GetPDFInfoTool()
        handlers[pdfInfo.name] = pdfInfo.handler
        toolSpecs[pdfInfo.name] = ToolSpec(name: pdfInfo.name, description: pdfInfo.description)

        let pdfRender: RenderPDFPageTool = RenderPDFPageTool()
        handlers[pdfRender.name] = pdfRender.handler
        toolSpecs[pdfRender.name] = ToolSpec(name: pdfRender.name, description: pdfRender.description)
        handlers["file_undo"] = { name, input, context in
            await Self.handleFileUndo(name: name, input: input, ctx: context)
        }
        toolSpecs["file_undo"] = ToolSpec(
            name: "file_undo",
            description: "撤销会话中的文件操作。支持按操作 ID、按文件路径、或撤销最近 N 个操作。"
        )
        handlers["file_operation_history"] = { name, input, context in
            await Self.handleFileOperationHistory(name: name, input: input, ctx: context)
        }
        toolSpecs["file_operation_history"] = ToolSpec(
            name: "file_operation_history",
            description: "查看当前会话的文件操作历史记录。"
        )
        handlers["capabilities_discover"] = { name, input, context in
            await Self.handleCapabilitiesDiscover(name: name, input: input, ctx: context)
        }
        toolSpecs["capabilities_discover"] = ToolSpec(
            name: "capabilities_discover",
            description: "搜索已启用的能力。传入搜索关键词。返回匹配的能力列表。"
        )
        handlers["capabilities_load"] = { name, input, context in
            await Self.handleCapabilitiesLoad(name: name, input: input, ctx: context)
        }
        toolSpecs["capabilities_load"] = ToolSpec(
            name: "capabilities_load",
            description: "加载一个能力到当前会话。传入 capabilities_discover 返回的能力名称。"
        )
    }

    // MARK: - Loop Tools (todo / complete / clarify)

    private static let todoChecklistLock: NSLock = NSLock()
    private nonisolated(unsafe) static var _todoChecklist: String = ""

    private static var todoChecklist: String {
        get { todoChecklistLock.withLock { _todoChecklist } }
        set { todoChecklistLock.withLock { _todoChecklist = newValue } }
    }

    private static func handleTodo(name: String, input: [String: Any], ctx: ToolContext) async -> ToolHandlerResult {
        let markdown: String = input["markdown"] as? String ?? ""
        guard !markdown.isEmpty else { return .handled("Error: markdown field required") }
        todoChecklist = markdown
        return .handled("✅ 任务清单已更新:\n\n\(markdown)")
    }

    private static func handleComplete(
        name: String, input: [String: Any], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let summary: String = input["summary"] as? String ?? ""
        guard AgentLoopTools.validate(summary: summary) else {
            return .handled(
                "Error: summary must be ≥30 characters of meaningful prose. "
                    + "Placeholders like 'done', 'ok', '已完成' are rejected. "
                    + "Describe what you did and how you verified."
            )
        }
        return .taskComplete(summary)
    }

    private static func handleClarify(name: String, input: [String: Any], ctx: ToolContext) async -> ToolHandlerResult {
        let question: String = input["question"] as? String ?? ""
        let options: [String] = input["options"] as? [String] ?? []
        let allowMultiple: Bool = input["allow_multiple"] as? Bool ?? false
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
    // swiftlint:disable:next function_body_length
    private static func handleReadFile(
        name: String, input: [String: Any], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let path: String = input["path"] as? String ?? input["file_path"] as? String ?? ""
        guard !path.isEmpty else {
            return .handled(ToolResponse.errResp(code: .invalidArgs, message: "path required").jsonString())
        }

        let fileURL: URL
        if path.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: path)
        } else if !ctx.projectFolder.isEmpty {
            fileURL = URL(fileURLWithPath: ctx.projectFolder).appendingPathComponent(path)
        } else {
            fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path)
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .handled(
                ToolResponse.errResp(
                    code: .notFound, message: "文件不存在: \(path)",
                    hint: "使用 list_files 查看目录内容"
                ).jsonString())
        }

        // 检查是否为目录
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
        if isDir.boolValue {
            let items: [String] = (try? FileManager.default.contentsOfDirectory(atPath: fileURL.path)) ?? []
            let list: String = items.sorted().joined(separator: "\n")
            return .handled(
                ToolResponse.okResp(
                    data: .object([
                        "type": .string("directory"),
                        "path": .string(fileURL.path),
                        "entries": .string(list),
                        "count": .number(Double(items.count))
                    ])
                ).jsonString())
        }

        // 行范围解析
        let lineOffset: Int? = input["offset"] as? Int
        let lineLimit: Int? = input["limit"] as? Int

        do {
            let content: String = try String(contentsOf: fileURL, encoding: .utf8)
            let lines: [String] = content.components(separatedBy: .newlines)
            let totalLines: Int = lines.count

            let output: String
            if let offset = lineOffset {
                let start: Int = max(0, offset - 1)
                let end: Int = lineLimit.map { min(totalLines, start + $0) } ?? totalLines
                output = lines[start..<end].enumerated().map { "\(start + $0 + 1): \($1)" }.joined(separator: "\n")
            } else {
                output = content
            }

            return .handled(
                ToolResponse.okResp(
                    data: .object([
                        "path": .string(fileURL.path),
                        "content": .string(output),
                        "total_lines": .number(Double(totalLines)),
                        "size": .number(Double(content.count))
                    ])
                ).jsonString())
        } catch {
            return .handled(
                ToolResponse.errResp(
                    code: .readError, message: error.localizedDescription
                ).jsonString())
        }
    }
    private static func handleWriteFile(
        name: String, input: [String: Any], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let path: String = input["path"] as? String ?? input["file_path"] as? String ?? ""
        let content: String = input["content"] as? String ?? ""
        let dryRun: Bool = input["dry_run"] as? Bool ?? false
        guard !path.isEmpty else {
            return .handled(
                ToolResponse.errResp(
                    code: .invalidArgs, message: "path required"
                ).jsonString())
        }

        if dryRun {
            return .handled(
                ToolResponse.okResp(
                    data: .object([
                        "dryRun": .bool(true),
                        "path": .string(path),
                        "size": .number(Double(content.count))
                    ])
                ).jsonString())
        }

        let beforeContent: String? = try? String(contentsOfFile: path, encoding: .utf8)
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            await FileOperationLog.shared.logWrite(
                path: path, content: content, beforeContent: beforeContent
            )
            // Git 自动 commit（安全写操作后）
            let parentDir: String = URL(fileURLWithPath: path).deletingLastPathComponent().path
            let shellCommand: String = """
                cd \(parentDir) && git add "\(path)" \
                && git commit -m "feat(agent): write \(URL(fileURLWithPath: path).lastPathComponent)" 2>/dev/null
                """
            _ = runShell("zsh", "-c", shellCommand)
            return .handled(
                ToolResponse.okResp(
                    data: .object([
                        "path": .string(path),
                        "size": .number(Double(content.count))
                    ])
                ).jsonString())
        } catch {
            return .handled(
                ToolResponse.errResp(
                    code: .writeError,
                    message: error.localizedDescription,
                    hint: "Check file permissions and parent directory existence"
                ).jsonString())
        }
    }
    private static func handleListFiles(
        name: String, input: [String: Any], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let pattern: String = input["pattern"] as? String ?? "*"
        let path: String = input["path"] as? String ?? ctx.projectFolder
        let dirURL: URL =
            path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : URL(
                fileURLWithPath: ctx.projectFolder.isEmpty
                    ? FileManager.default.currentDirectoryPath : ctx.projectFolder
            ).appendingPathComponent(path)

        guard FileManager.default.fileExists(atPath: dirURL.path) else {
            return .handled(ToolResponse.errResp(code: .notFound, message: "目录不存在: \(path)").jsonString())
        }

        let shellResult: String = runShell(
            "find", dirURL.path, "-maxdepth", "1", "-name", pattern, "-not", "-name", ".*", "|", "sort"
        )
        let files: [String] = shellResult.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        let display: [String] = files.map { file -> String in
            let absPath: String = file.hasPrefix("/") ? file : dirURL.appendingPathComponent(file).path
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: absPath, isDirectory: &isDir)
            return isDir.boolValue ? "\(file)/" : file
        }
        return .handled(
            ToolResponse.okResp(
                data: .object([
                    "path": .string(dirURL.path),
                    "pattern": .string(pattern),
                    "files": .string(display.joined(separator: "\n")),
                    "count": .number(Double(files.count))
                ])
            ).jsonString())
    }

    private static func runShell(_ args: String...) -> String {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", args.joined(separator: " ")]
        let pipe: Pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    private static func handleSearchFiles(
        name: String, input: [String: Any], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let pattern: String = input["pattern"] as? String ?? ""
        let path: String = input["path"] as? String ?? ctx.projectFolder
        guard !pattern.isEmpty else {
            return .handled(ToolResponse.errResp(code: .invalidArgs, message: "pattern required").jsonString())
        }
        let dirURL: URL =
            path.isEmpty
            ? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            : (path.hasPrefix("/")
                ? URL(fileURLWithPath: path)
                : URL(fileURLWithPath: ctx.projectFolder).appendingPathComponent(path))

        // 使用 grep -r 做简要搜索
        let shellResult: String = runShell(
            "grep", "-rn", "--include=*.swift", "--include=*.md", "--include=*.txt",
            "--include=*.json", "--include=*.py", "--include=*.sh",
            "-e", "\"\(pattern)\"", dirURL.path, "2>/dev/null", "|", "head", "-30"
        )
        let lines: [String] = shellResult.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return .handled(
            ToolResponse.okResp(
                data: .object([
                    "path": .string(dirURL.path),
                    "pattern": .string(pattern),
                    "matches": .string(lines.joined(separator: "\n")),
                    "match_count": .number(Double(lines.count))
                ])
            ).jsonString())
    }
    // swiftlint:disable:next function_body_length
    private static func handleExecuteShell(
        name: String, input: [String: Any], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let command: String = input["command"] as? String ?? ""
        guard !command.isEmpty else {
            return .handled(ToolResponse.errResp(code: .invalidArgs, message: "command required").jsonString())
        }

        let cwd: URL? =
            (input["cwd"] as? String).map { URL(fileURLWithPath: $0) }
            ?? (ctx.projectFolder.isEmpty ? nil : URL(fileURLWithPath: ctx.projectFolder))
        let timeout: TimeInterval = input["timeout"] as? TimeInterval ?? 30

        let firstWord: String =
            command.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces).first ?? ""
        let dangerousCommands: Set<String> = ["rm", "sudo", "shutdown", "reboot", "mkfs", "dd", "kill"]
        if dangerousCommands.contains(firstWord) {
            return .handled(
                ToolResponse.errResp(
                    code: .permissionDenied,
                    message: "命令 '\(firstWord)' 不在白名单中",
                    hint: "危险命令已被阻止"
                ).jsonString())
        }

        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        if let cwd = cwd { process.currentDirectoryURL = cwd }

        let stdoutPipe: Pipe = Pipe()
        let stderrPipe: Pipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            let deadline: Date = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            if process.isRunning {
                process.terminate()
                return .handled(
                    ToolResponse.errResp(
                        code: .timeout, message: "命令超时 (\(timeout)s)"
                    ).jsonString())
            }
            process.waitUntilExit()

            let stdout: String =
                String(
                    data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
                ) ?? ""
            let stderr: String =
                String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
                ) ?? ""

            var execResult: [String: JSONValue] = [
                "exit_code": .number(Double(process.terminationStatus)),
                "stdout": .string(stdout)
            ]
            if !stderr.isEmpty { execResult["stderr"] = .string(stderr) }
            return .handled(ToolResponse.okResp(data: .object(execResult)).jsonString())
        } catch {
            return .handled(
                ToolResponse.errResp(
                    code: .executionError, message: error.localizedDescription
                ).jsonString())
        }
    }
    private static func handlePatentSearch(
        name: String, input: [String: Any], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let query: String = input["query"] as? String ?? ""
        guard !query.isEmpty else { return .handled("Error: query required") }
        return .handled("[patent_search stub] query=\(query)")
    }
    private static func handleLegalStatusQuery(
        name: String, input: [String: Any], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let patentNumber: String = input["patent_number"] as? String ?? ""
        guard !patentNumber.isEmpty else { return .handled("Error: patent_number required") }
        return .handled("[legal_status_query stub] patent=\(patentNumber)")
    }
    // MARK: - Capability Tools

    private static func handleCapabilitiesDiscover(
        name: String, input: [String: Any], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let query: String = (input["query"] as? String ?? "").lowercased()
        let registry: CapabilityRegistry = CapabilityRegistry()
        var matches: [String] = []

        for cap in await registry.listCapabilities() {
            if query.isEmpty || cap.name.lowercased().contains(query) || cap.displayName.lowercased().contains(query)
                || cap.description.lowercased().contains(query) {
                let net: String = cap.metadata.requiresNetwork ? " 🌐" : ""
                matches.append("- \(cap.displayName) (`\(cap.name)`)\(net) — \(cap.description)")
            }
        }

        if matches.isEmpty {
            return .handled("没有找到匹配的能力。尝试更宽的关键词。")
        }
        return .handled("【匹配的能力】\n" + matches.joined(separator: "\n"))
    }

    private static func handleCapabilitiesLoad(
        name: String, input: [String: Any], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let capName: String = input["name"] as? String ?? ""
        guard !capName.isEmpty else { return .handled("Error: name field required") }

        let registry: CapabilityRegistry = CapabilityRegistry()
        guard let cap = await registry.listCapabilities().first(where: { $0.name == capName }) else {
            return .handled("Error: 未找到能力 '\(capName)'。先使用 capabilities_discover 查找可用能力。")
        }

        // 记录 load 以更新 schema
        await CapabilityLoadBuffer.shared.recordLoad(capName)

        let details: String = """
            已加载能力: \(cap.displayName) (\(cap.name))
            描述: \(cap.description)
            来源: \(cap.source.rawValue)
            权限: \(cap.permission.rawValue)
            🌐 需要网络: \(cap.metadata.requiresNetwork)
            典型场景: \(cap.metadata.typicalUseCases.joined(separator: ", "))
            """
        return .handled(details)
    }

    private static func handleKnowledgeSearch(
        name: String, input: [String: Any], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let query: String = input["query"] as? String ?? ""
        guard !query.isEmpty else { return .handled("Error: query required") }
        return .handled("[knowledge_search stub] query=\(query)")
    }

    // MARK: - File Undo Tools

    private static func handleFileUndo(
        name: String, input: [String: Any], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let opId: String? = input["operation_id"] as? String
        let undoPath: String? = input["path"] as? String
        let undoCount: Int = input["count"] as? Int ?? 1

        let log: FileOperationLog = FileOperationLog.shared
        if let opId = opId, let uuid = UUID(uuidString: opId) {
            let result: String = await log.undo(opId: uuid)
            return .handled(result)
        } else if let undoPath = undoPath {
            let results: [String] = await log.undoAll(path: undoPath)
            return .handled(results.joined(separator: "\n"))
        } else {
            let results: [String] = await log.undoLast(count: undoCount)
            return .handled(results.joined(separator: "\n"))
        }
    }

    private static func handleFileOperationHistory(
        name: String, input: [String: Any], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let historyPath: String? = input["path"] as? String
        let log: FileOperationLog = FileOperationLog.shared
        let history: [FileOp] = await log.history(path: historyPath)
        if history.isEmpty {
            return .handled("尚无文件操作记录。")
        }
        var lines: [String] = []
        for operation in history {
            let marker: String = operation.canUndo ? "↩️" : "➡️"
            let detail: String =
                operation.beforeContent.map { _ in
                    " (\(operation.afterContent?.count ?? 0) chars)"
                } ?? ""
            lines.append(
                "\(marker) `\(operation.path)` [\(operation.kind)]\(detail)  "
                    + "\(operation.timestamp.formatted(date: .omitted, time: .shortened))"
            )
        }
        return .handled(lines.joined(separator: "\n"))
    }

    // MARK: - Dispatch with Hooks

    /// 带 Hooks 分派: 先执行 preToolUse hooks (可 block)，再执行工具，最后 postToolUse hooks
    public func dispatchWithHooks(
        name: String,
        input: [String: Any],
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
