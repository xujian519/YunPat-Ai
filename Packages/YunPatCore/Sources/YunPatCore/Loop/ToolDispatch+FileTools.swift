import Foundation
import os

private let fileToolsLogger = Logger(subsystem: "com.yunpat", category: "execute_shell")

// MARK: - File Tools 注册 & 处理

extension ToolDispatch {

    func registerFileTools() {
        // 文件工具 — 同时提供 read_file/write_file（兼容旧调用方）和 TypedTool 版本
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
    }

    // MARK: - Read / Write / List / Search / Shell

    // swiftlint:disable:next function_body_length
    private static func handleReadFile(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let path: String = input["path"]?.stringValue ?? input["file_path"]?.stringValue ?? ""
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

        let lineOffset: Int? = input["offset"]?.intValue
        let lineLimit: Int? = input["limit"]?.intValue

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
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let path: String = input["path"]?.stringValue ?? input["file_path"]?.stringValue ?? ""
        let content: String = input["content"]?.stringValue ?? ""
        let dryRun: Bool = input["dry_run"]?.boolValue ?? false
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
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let pattern: String = input["pattern"]?.stringValue ?? "*"
        let path: String = input["path"]?.stringValue ?? ctx.projectFolder
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
        do {
            try process.run()
        } catch {
            fileToolsLogger.error("Failed to run process: \(error, privacy: .public)")
            return "Error: \(error.localizedDescription)"
        }
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static func handleSearchFiles(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let pattern: String = input["pattern"]?.stringValue ?? ""
        let path: String = input["path"]?.stringValue ?? ctx.projectFolder
        guard !pattern.isEmpty else {
            return .handled(ToolResponse.errResp(code: .invalidArgs, message: "pattern required").jsonString())
        }
        let dirURL: URL =
            path.isEmpty
            ? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            : (path.hasPrefix("/")
                ? URL(fileURLWithPath: path)
                : URL(fileURLWithPath: ctx.projectFolder).appendingPathComponent(path))

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
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let command: String = input["command"]?.stringValue ?? ""
        guard !command.isEmpty else {
            return .handled(ToolResponse.errResp(code: .invalidArgs, message: "command required").jsonString())
        }

        let cwd: URL? =
            input["cwd"]?.stringValue.map { URL(fileURLWithPath: $0) }
            ?? (ctx.projectFolder.isEmpty ? nil : URL(fileURLWithPath: ctx.projectFolder))
        let timeout: TimeInterval = input["timeout"]?.doubleValue ?? 30

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

    // MARK: - File Undo

    private static func handleFileUndo(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let opId: String? = input["operation_id"]?.stringValue
        let undoPath: String? = input["path"]?.stringValue
        let undoCount: Int = input["count"]?.intValue ?? 1

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
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let historyPath: String? = input["path"]?.stringValue
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
}
