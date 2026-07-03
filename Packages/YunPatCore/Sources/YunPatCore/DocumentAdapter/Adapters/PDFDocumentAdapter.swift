import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

/// PDF 文档适配器 — 使用 PDFKit 解析
///
/// macOS 原生支持：
/// - 提取所有页面文本
/// - 按页面分节
/// - 提取元数据（作者、页数、创建/修改日期）
///
/// 在非 Apple 平台上返回 unsupportedFormat。
public struct PDFDocumentAdapter: DocumentAdapter {
    public let supportedExtensions: Set<String> = ["pdf"]

    public init() {}

    public func parse(url: URL) async throws -> DocumentContent {
        let data = try Data(contentsOf: url)
        return try await parse(data: data, fileName: url.lastPathComponent)
    }

    public func parse(data: Data, fileName: String) async throws -> DocumentContent {
        #if canImport(PDFKit)
        return try parseWithPDFKit(data: data, fileName: fileName)
        #else
        throw DocumentAdapterError.unsupportedFormat("pdf (PDFKit unavailable)")
        #endif
    }

    #if canImport(PDFKit)
    private func parseWithPDFKit(data: Data, fileName: String) throws -> DocumentContent {
        guard let pdfDoc = PDFDocument(data: data) else {
            throw DocumentAdapterError.parseFailed("无法加载 PDF 文档")
        }

        let pageCount: Int = pdfDoc.pageCount
        var allText: String = ""
        var sections: [DocumentSection] = []

        for pageIndex in 0..<pageCount {
            guard let page = pdfDoc.page(at: pageIndex) else { continue }

            let pageText: String = page.string ?? ""
            let pageLabel: String = page.label ?? "第 \(pageIndex + 1) 页"
            let pageNum: Int = pageIndex + 1
            let heading: String = "第 \(pageNum) 页" + (pageLabel != "第 \(pageNum) 页" ? " (\(pageLabel))" : "")

            allText += "--- \(heading) ---\n\(pageText)\n\n"
            sections.append(DocumentSection(
                heading: heading, level: 1, content: pageText, pageNumber: pageNum
            ))
        }

        let attrs: [AnyHashable: Any]? = pdfDoc.documentAttributes
        let author: String? = attrs?[PDFDocumentAttribute.authorAttribute] as? String
        let createdDate: Date? = attrs?[PDFDocumentAttribute.creationDateAttribute] as? Date
        let modifiedDate: Date? = attrs?[PDFDocumentAttribute.modificationDateAttribute] as? Date

        let metadata = DocumentMetadata(
            fileName: fileName, fileSize: data.count, pageCount: pageCount,
            author: author, createdDate: createdDate, modifiedDate: modifiedDate
        )

        return DocumentContent(text: allText, metadata: metadata, sections: sections)
    }
    #endif
}
