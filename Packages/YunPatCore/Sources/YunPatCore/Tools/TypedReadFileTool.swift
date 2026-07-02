import Foundation

/// read_file 强类型实现 — 读取文件内容，支持 offset/limit 分段
struct TypedReadFileTool: TypedTool {
    let name: String = "typed_read_file"
    let description: String = "读取文件内容，支持 offset/limit 分段读取"
    var parameters: String {
        "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"文件路径"
            + "（绝对或相对项目根目录）\"},\"offset\":{\"type\":\"integer\",\"description\":\"起始行号（1-based，默认1）\"},"
            + "\"limit\":{\"type\":\"integer\",\"description\":\"读取行数（默认全部）\"}},\"required\":[\"path\"]}"
    }

    struct Args: Decodable, Sendable {
        let path: String
        let offset: Int?
        let limit: Int?
    }

    func execute(input: Args, context: ToolContext) async throws -> ToolResponse {
        let fileURL: URL
        if input.path.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: input.path)
        } else if !context.projectFolder.isEmpty {
            fileURL = URL(fileURLWithPath: context.projectFolder).appendingPathComponent(input.path)
        } else {
            fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(input.path)
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ToolResponse.errResp(code: .notFound, message: "文件不存在: \(input.path)", hint: "使用 list_files 查看目录内容")
        }

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
        if isDir.boolValue {
            let items: [String] = (try? FileManager.default.contentsOfDirectory(atPath: fileURL.path)) ?? []
            return ToolResponse.okResp(
                data: .object([
                    "type": .string("directory"),
                    "path": .string(fileURL.path),
                    "entries": .string(items.sorted().joined(separator: "\n")),
                    "count": .number(Double(items.count))
                ]))
        }

        let content: String = try String(contentsOf: fileURL, encoding: .utf8)
        let lines: [String] = content.components(separatedBy: "\n")

        let startLine: Int = max(0, (input.offset ?? 1) - 1)
        let limit: Int = input.limit ?? lines.count
        let endIdx: Int = min(startLine + limit, lines.count)
        let selected: [String] = Array(lines[startLine..<endIdx])

        let numbered: String = selected.enumerated().map { index, line in
            "\(startLine + index + 1): \(line)"
        }.joined(separator: "\n")

        return ToolResponse.okResp(
            data: .object([
                "path": .string(fileURL.path),
                "content": .string(numbered),
                "lineCount": .number(Double(selected.count)),
                "truncated": .bool(endIdx < lines.count)
            ]))
    }
}
