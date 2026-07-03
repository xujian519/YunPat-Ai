import Foundation

/// patent_document_read 工具 — 通过 DocumentAdapterRegistry 解析文档
///
/// 向 ToolDispatch 注册 `patent_document_read` 工具，
/// 允许 Agent 循环中读取 PDF/XLSX/DOCX/PPTX/TXT 等格式。
///
/// 注册方式：
/// ```swift
/// let registry = await DocumentAdapterProvider.createDefaultRegistry()
/// PatentDocumentTool.register(to: ToolDispatch.shared, registry: registry)
/// ```
public enum PatentDocumentTool {

    /// 工具名称
    public static let toolName: String = "patent_document_read"

    /// 工具描述
    public static let toolDescription: String = "读取并解析专利相关文档（PDF/XLSX/DOCX/PPTX/TXT/CSV/MD），返回纯文本内容供 AI 分析"

    // MARK: - Registration

    /// 注册到 ToolDispatch
    public static func register(to dispatch: ToolDispatch = .shared, registry: DocumentAdapterRegistry) {
        dispatch.register(
            name: toolName,
            description: toolDescription,
            handler: { _, args, _ in
                await PatentDocumentTool.handle(args: args, registry: registry)
            }
        )
    }

    // MARK: - Handler

    private static func handle(
        args: [String: JSONValue], registry: DocumentAdapterRegistry
    ) async -> ToolHandlerResult {
        guard case .string(let path) = args["path"] ?? args["file_path"] else {
            return .handled("Error: 需要 path 或 file_path 参数")
        }

        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let ext = url.pathExtension.lowercased()

        guard await registry.adapter(for: ext) != nil else {
            let supported: String = await registry.registeredExtensions.joined(separator: ", ")
            return .handled("Error: 不支持的格式: .\(ext)。支持的格式: \(supported)")
        }

        do {
            let content: DocumentContent = try await registry.parse(url: url)
            var result: String = "文件: \(content.metadata.fileName)\n"
            result += "大小: \(formatBytes(content.metadata.fileSize))\n"
            if let pages = content.metadata.pageCount {
                result += "页数/行数: \(pages)\n"
            }
            if let author = content.metadata.author {
                result += "作者: \(author)\n"
            }

            result += "\n--- 内容摘要 ---\n"
            let preview = content.text.prefix(3000)
            result += preview
            if content.text.count > 3000 {
                result += "\n\n... [内容过长，仅显示前 3000 字符，共 \(content.text.count) 字符]"
            }

            if !content.sections.isEmpty {
                result += "\n\n--- 文档目录 (\(content.sections.count) 节) ---\n"
                for section in content.sections {
                    let indent = String(repeating: "  ", count: max(0, section.level - 1))
                    let page: String = section.pageNumber.map { " (第 \($0) 页)" } ?? ""
                    result += "\(indent)- \(section.heading)\(page)\n"
                }
            }

            return .handled(result)
        } catch let error as DocumentAdapterError {
            return .handled("Error: \(error.localizedDescription)")
        } catch {
            return .handled("Error: 读取失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
