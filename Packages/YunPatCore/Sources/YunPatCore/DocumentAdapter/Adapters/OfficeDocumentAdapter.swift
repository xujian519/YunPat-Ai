import Foundation

/// Office 文档适配器 — 解析 DOCX / XLSX / PPTX
///
/// 这些格式本质上是 ZIP 压缩包内含 XML 文件。本适配器：
/// 1. 通过系统 `unzip -p` 提取关键 XML 文件到 stdout
/// 2. 使用 Foundation XMLParser 提取文本内容
/// 3. 结构化输出（按章节/工作表/幻灯片分节）
///
/// 注意：依赖系统 `/usr/bin/unzip` 命令。
public struct OfficeDocumentAdapter: DocumentAdapter {
    public let supportedExtensions: Set<String> = ["docx", "xlsx", "pptx"]

    public init() {}

    public func parse(url: URL) async throws -> DocumentContent {
        let data = try Data(contentsOf: url)
        return try await parse(data: data, fileName: url.lastPathComponent)
    }

    public func parse(data: Data, fileName: String) async throws -> DocumentContent {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        switch ext {
        case "docx": return try await parseDOCX(url: tempURL, data: data, fileName: fileName)
        case "xlsx": return try await parseXLSX(url: tempURL, data: data, fileName: fileName)
        case "pptx": return try await parsePPTX(url: tempURL, data: data, fileName: fileName)
        default: throw DocumentAdapterError.unsupportedFormat(ext)
        }
    }

    // MARK: - DOCX

    private func parseDOCX(url: URL, data: Data, fileName: String) async throws -> DocumentContent {
        let xml = try unzipXML(path: url.path, internalPath: "word/document.xml")
        let text = extractTextFromXML(xml)

        let sections: [DocumentSection] = try extractSectionsFromDOCX(path: url.path) ?? {
            let paras = text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
            return zip(paras.indices, paras).map { (index, para) in
                DocumentSection(heading: "段落 \(index + 1)", level: 2, content: para)
            }
        }()

        let metadata = DocumentMetadata(
            fileName: fileName, fileSize: data.count,
            pageCount: sections.count
        )
        return DocumentContent(text: text, metadata: metadata, sections: sections)
    }

    private func extractSectionsFromDOCX(path: String) throws -> [DocumentSection]? {
        // Try headings from word/document.xml
        let xml = try unzipXML(path: path, internalPath: "word/document.xml")
        var sections: [DocumentSection] = []
        var currentText: String = ""

        // Simple tag-based extraction: find <w:p> paragraphs and <w:pStyle w:val="Heading"/> headings
        let parser = SimpleXMLParser(text: xml)
        let parsed = parser.parse()

        for element in parsed {
            if element.tag == "w:pStyle", element.attributes["w:val"]?.hasPrefix("Heading") == true {
                if !currentText.isEmpty {
                    sections.append(DocumentSection(
                        heading: currentText, level: max(sections.count, 1)
                    ))
                    currentText = ""
                }
            } else if element.tag == "w:t" {
                currentText += element.content
            }
        }
        if !currentText.isEmpty {
            sections.append(DocumentSection(heading: currentText, level: 2))
        }
        return sections.isEmpty ? nil : sections
    }

    // MARK: - XLSX

    private func parseXLSX(url: URL, data: Data, fileName: String) async throws -> DocumentContent {
        // Read shared strings
        let sharedStrings: [String]
        if let ssXML = try? unzipXML(path: url.path, internalPath: "xl/sharedStrings.xml") {
            sharedStrings = extractXLSXSharedStrings(from: ssXML)
        } else {
            sharedStrings = []
        }

        // Read all worksheets
        var text: String = ""
        var sheetIndex: Int = 0
        var sections: [DocumentSection] = []

        while true {
            let sheetPath: String = "xl/worksheets/sheet\(sheetIndex + 1).xml"
            guard let sheetXML = try? unzipXML(path: url.path, internalPath: sheetPath) else { break }
            sheetIndex += 1

            let sheetContent: String = extractXLSXSheet(from: sheetXML, sharedStrings: sharedStrings)
            let sheetName: String = extractSheetName(from: sheetXML) ?? "工作表 \(sheetIndex)"
            text += "--- \(sheetName) ---\n\(sheetContent)\n\n"
            sections.append(DocumentSection(
                heading: sheetName, level: 1, content: sheetContent
            ))
        }

        let metadata = DocumentMetadata(
            fileName: fileName, fileSize: data.count,
            pageCount: sheetIndex
        )
        return DocumentContent(text: text, metadata: metadata, sections: sections)
    }

    private func extractXLSXSharedStrings(from xml: String) -> [String] {
        var strings: [String] = []
        // <si><t>text</t></si>
        let siBlocks = extractTagBlocks(xml, tag: "si")
        for block in siBlocks {
            if let tContent = extractTagContent(block, tag: "t") {
                strings.append(tContent)
            }
        }
        return strings
    }

    private func extractXLSXSheet(from xml: String, sharedStrings: [String]) -> String {
        // Extract all <c> cells with their values
        let rows = extractTagBlocks(xml, tag: "row")
        var output: String = ""
        for (rowIdx, rowXML) in rows.enumerated() {
            let cells = extractTagBlocks(rowXML, tag: "c")
            let rowValues: [String] = cells.map { cellXML in
                let type = extractAttribute(cellXML, tag: "c", attr: "t")
                if let value = extractTagContent(cellXML, tag: "v") {
                    if type == "s", let idx = Int(value), idx < sharedStrings.count {
                        return sharedStrings[idx]
                    }
                    return value
                }
                return ""
            }
            output += "行\(rowIdx + 1): \(rowValues.joined(separator: "\t"))\n"
        }
        return output
    }

    private func extractSheetName(from xml: String) -> String? {
        // Try to find sheet name from the workbook relationship
        // Fallback: check r:name or name attribute
        nil
    }

    // MARK: - PPTX

    private func parsePPTX(url: URL, data: Data, fileName: String) async throws -> DocumentContent {
        var allText: String = ""
        var sections: [DocumentSection] = []
        var slideIndex: Int = 0

        while true {
            let slidePath: String = "ppt/slides/slide\(slideIndex + 1).xml"
            guard let slideXML = try? unzipXML(path: url.path, internalPath: slidePath) else { break }
            slideIndex += 1

            let text = extractTextFromXML(slideXML)
            let heading: String = "幻灯片 \(slideIndex)"
            allText += "--- \(heading) ---\n\(text)\n\n"
            sections.append(DocumentSection(
                heading: heading, level: 1, content: text, pageNumber: slideIndex
            ))
        }

        let metadata = DocumentMetadata(
            fileName: fileName, fileSize: data.count,
            pageCount: slideIndex
        )
        return DocumentContent(text: allText, metadata: metadata, sections: sections)
    }

    // MARK: - Helpers

    /// 从 zip 中提取指定内部文件的 text 内容（通过 unzip -p）
    private func unzipXML(path: String, internalPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", path, internalPath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DocumentAdapterError.parseFailed("unzip 失败 (exit \(process.terminationStatus)): \(internalPath)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            throw DocumentAdapterError.parseFailed("无法解码 XML: \(internalPath)")
        }
        return text
    }

    /// 从 XML 中提取所有文本节点的内容，用空格连接
    private func extractTextFromXML(_ xml: String) -> String {
        var results: [String] = []
        var searchRange: Range<String.Index> = xml.startIndex..<xml.endIndex

        while true {
            // Find <text> or <t> content — common Office XML text tags
            guard let tStart = xml.range(of: ">", range: searchRange)?.upperBound else { break }
            guard let tEnd = xml.range(of: "</", range: tStart..<xml.endIndex)?.lowerBound else { break }

            let content = String(xml[tStart..<tEnd])
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                results.append(content)
            }
            searchRange = tEnd..<xml.endIndex
        }

        return results.joined(separator: "\n")
    }

    /// 提取所有指定标签块的内容（含内部子标签）
    private func extractTagBlocks(_ xml: String, tag: String) -> [String] {
        var results: [String] = []
        var searchRange: Range<String.Index> = xml.startIndex..<xml.endIndex

        while true {
            guard let openStart = xml.range(of: "<\(tag)", range: searchRange) else { break }
            let openEnd: String.Index
            if let closeBracket = xml.range(of: ">", range: openStart.upperBound..<xml.endIndex) {
                openEnd = closeBracket.upperBound
            } else {
                break
            }

            let closeTag: String = "</\(tag)>"
            guard let closeStart = xml.range(of: closeTag, range: openEnd..<xml.endIndex)?.upperBound else { break }

            results.append(String(xml[openStart.lowerBound..<closeStart]))
            searchRange = closeStart..<xml.endIndex
        }

        return results
    }

    /// 提取标签的文本内容
    private func extractTagContent(_ xml: String, tag: String) -> String? {
        let openTag: String = "<\(tag)>"
        let closeTag: String = "</\(tag)>"
        guard let start = xml.range(of: openTag)?.upperBound,
              let end = xml.range(of: closeTag, range: start..<xml.endIndex)?.lowerBound
        else { return nil }
        return String(xml[start..<end])
    }

    /// 提取标签属性值
    private func extractAttribute(_ xml: String, tag: String, attr: String) -> String? {
        let pattern: String = "\(attr)=\""
        guard let start = xml.range(of: pattern)?.upperBound,
              let end = xml.range(of: "\"", range: start..<xml.endIndex)?.lowerBound
        else { return nil }
        return String(xml[start..<end])
    }
}

// MARK: - Simple XML Parser (tag-based, not schema-aware)

private struct SimpleXMLElement {
    let tag: String
    let attributes: [String: String]
    let content: String
}

private struct SimpleXMLParser {
    let text: String

    func parse() -> [SimpleXMLElement] {
        var elements: [SimpleXMLElement] = []
        var searchRange: Range<String.Index> = text.startIndex..<text.endIndex

        while true {
            guard let openStart = text.range(of: "<", range: searchRange) else { break }
            guard let tagEnd = text.range(of: ">", range: openStart.upperBound..<text.endIndex) else { break }

            let header: Substring = text[openStart.upperBound..<tagEnd.lowerBound]
            let parts = header.split(separator: " ", maxSplits: 1)
                    let tag: String = String(parts[0])

            // Skip comments and processing instructions
            if tag.hasPrefix("!") || tag.hasPrefix("?") || tag == "?xml" {
                searchRange = tagEnd.upperBound..<text.endIndex
                continue
            }

            // Self-closing tag
            if header.hasSuffix("/") || tag.hasPrefix("/") {
                searchRange = tagEnd.upperBound..<text.endIndex
                continue
            }

            // Attribute parsing
            var attrs: [String: String] = [:]
            if parts.count > 1 {
                let attrStr = String(parts[1])
                var attrRange: Range<String.Index> = attrStr.startIndex..<attrStr.endIndex
                while let eqPos = attrStr.range(of: "=", range: attrRange) {
                    let name = attrStr[attrRange.lowerBound..<eqPos.lowerBound]
                        .trimmingCharacters(in: .whitespaces)
                    guard let qStart = attrStr.range(of: "\"", range: eqPos.upperBound..<attrStr.endIndex)?.upperBound,
                          let qEnd = attrStr.range(of: "\"", range: qStart..<attrStr.endIndex)?.lowerBound
                    else { break }
                    attrs[String(name)] = String(attrStr[qStart..<qEnd])
                    if let nextQ = attrStr.range(of: "\"", range: qEnd..<attrStr.endIndex) {
                        attrRange = nextQ.upperBound..<attrStr.endIndex
                    } else {
                        break
                    }
                }
            }

            let closeTag: String = "</\(tag)>"
            guard let closeStart = text.range(of: closeTag, range: tagEnd.upperBound..<text.endIndex) else {
                searchRange = tagEnd.upperBound..<text.endIndex
                continue
            }

            let content = String(text[tagEnd.upperBound..<closeStart.lowerBound])
            elements.append(SimpleXMLElement(tag: tag, attributes: attrs, content: content))
            searchRange = closeStart.upperBound..<text.endIndex
        }

        return elements
    }
}
