import Foundation

/// 纯文本文档适配器 — 解析无格式文本文件
///
/// 支持扩展名: txt, md, json, xml, yaml, yml, log, ini, cfg, properties, env, csv (fallback)
///
/// 对 Markdown 尝试提取标题作为分节信息。
/// 大文件（> 1MB）自动截断前 100KB 并注明。
public struct PlainTextDocumentAdapter: DocumentAdapter {
    public let supportedExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "xml", "yaml", "yml",
        "log", "ini", "cfg", "properties", "env", "rtf"
    ]

    private let maxPreviewBytes: Int = 100_000

    public init() {}

    public func parse(url: URL) async throws -> DocumentContent {
        let data = try Data(contentsOf: url)
        return try await parse(data: data, fileName: url.lastPathComponent)
    }

    public func parse(data: Data, fileName: String) async throws -> DocumentContent {
        guard let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .ascii)
        else {
            throw DocumentAdapterError.parseFailed("无法解码文本文件")
        }

        let ext = (fileName as NSString).pathExtension.lowercased()
        let isMarkdown: Bool = ext == "md" || ext == "markdown"

        let truncated: String
        let note: String
        if data.count > maxPreviewBytes {
            let endIndex = content.index(content.startIndex, offsetBy: min(maxPreviewBytes, content.count))
            truncated = String(content[..<endIndex])
            note = "\n\n[文件过大: \(data.count) bytes，仅显示前 \(maxPreviewBytes) bytes]"
        } else {
            truncated = content
            note = ""
        }

        let text: String = truncated + note

        // Markdown 提取标题分节
        var sections: [DocumentSection] = []
        if isMarkdown {
            let lines = truncated.components(separatedBy: .newlines)
            var currentSection: String = ""
            var currentHeading: String = ""
            var currentLevel: Int = 0

            for line in lines {
                if line.hasPrefix("#") {
                    // 保存前一节
                    if !currentHeading.isEmpty {
                        sections.append(DocumentSection(
                            heading: currentHeading, level: currentLevel, content: currentSection
                        ))
                    }
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let level: Int = trimmed.prefix(while: { $0 == "#" }).count
                    currentHeading = String(trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))
                    currentLevel = level
                    currentSection = ""
                } else {
                    if !currentSection.isEmpty { currentSection += "\n" }
                    currentSection += line
                }
            }
            // 最后一节
            if !currentHeading.isEmpty {
                sections.append(DocumentSection(
                    heading: currentHeading, level: currentLevel, content: currentSection
                ))
            }
        }

        let metadata = DocumentMetadata(
            fileName: fileName, fileSize: data.count,
            pageCount: isMarkdown ? max(sections.count, 1) : nil
        )

        return DocumentContent(text: text, metadata: metadata, sections: sections)
    }
}
