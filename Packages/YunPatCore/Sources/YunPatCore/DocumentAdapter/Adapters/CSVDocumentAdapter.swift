import Foundation

/// CSV 文档适配器 — 解析逗号分隔值文件
///
/// 支持：
/// - 标准 CSV（逗号分隔）
/// - TSV（制表符分隔，自动检测）
/// - 自动检测标题行
/// - 所有值视为字符串（不进行类型推断）
public struct CSVDocumentAdapter: DocumentAdapter {
    public let supportedExtensions: Set<String> = ["csv", "tsv"]

    private let chunkRowLimit: Int = 500  // 每块最多行数，超出截断并注明

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
            throw DocumentAdapterError.parseFailed("无法解码 CSV 文件（UTF-8/16/ASCII）")
        }

        let ext = (fileName as NSString).pathExtension.lowercased()
        let delimiter: Character = ext == "tsv" ? "\t" : ","
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard !lines.isEmpty else {
            let metadata = DocumentMetadata(fileName: fileName, fileSize: data.count)
            return DocumentContent(text: "(空文件)", metadata: metadata)
        }

        // 解析第一行判断是否为标题
        let headerRow: [String] = parseCSVLine(lines[0], delimiter: delimiter)
        let hasHeader: Bool = !headerRow.isEmpty && headerRow.allSatisfy { !$0.isEmpty }
        var text: String = ""
        let totalRows: Int = hasHeader ? lines.count - 1 : lines.count
        let displayedRows: Int = min(totalRows, chunkRowLimit)

        if hasHeader {
            text += "表头: \(headerRow.joined(separator: " | "))\n"
        }
        text += "行数: \(totalRows) 行"
        if totalRows > chunkRowLimit { text += " (仅显示前 \(chunkRowLimit) 行)" }
        text += "\n\n"

        let startIdx: Int = hasHeader ? 1 : 0
        for rowIdx in startIdx..<(startIdx + displayedRows) {
            let row = parseCSVLine(lines[rowIdx], delimiter: delimiter)
            text += "行\(rowIdx - startIdx + 1): \(row.joined(separator: " | "))\n"
        }

        let metadata = DocumentMetadata(
            fileName: fileName, fileSize: data.count,
            pageCount: totalRows
        )

        return DocumentContent(text: text, metadata: metadata)
    }

    /// 解析单行 CSV，处理引号内的逗号
    private func parseCSVLine(_ line: String, delimiter: Character) -> [String] {
        var result: [String] = []
        var current: String = ""
        var inQuotes: Bool = false

        for char in line {
            switch char {
            case "\"":
                inQuotes.toggle()
            case delimiter where !inQuotes:
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default:
                current.append(char)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }
}
