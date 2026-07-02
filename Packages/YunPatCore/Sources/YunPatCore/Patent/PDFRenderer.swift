import CoreImage
import Foundation
import PDFKit

// MARK: - PDFRenderer

/// PDF 多页渲染管线 — 对齐 Osaurus loadImageOrPDF + loadPDFPage 设计（Plugin.swift:54-138）
///
/// 能力：
/// - 多页索引（1-indexed），越界检查并返回友好错误
/// - DPI 控制（默认 300），72 dpi 为 PDF 原生 point 密度
/// - sRGB 色彩空间 + 白底填充
/// - 元数据提取（页数、尺寸、加密状态）
public enum PDFRenderer: Sendable {

    public struct PageInfo: Sendable, Codable {
        public let pageCount: Int
        public let pageWidthPoints: Double
        public let pageHeightPoints: Double
        public let pageWidthInches: Double
        public let pageHeightInches: Double
        public let isEncrypted: Bool
        public let isLocked: Bool
        public let filePath: String

        public init(
            pageCount: Int, pageWidthPoints: Double, pageHeightPoints: Double,
            pageWidthInches: Double, pageHeightInches: Double,
            isEncrypted: Bool, isLocked: Bool, filePath: String
        ) {
            self.pageCount = pageCount
            self.pageWidthPoints = pageWidthPoints
            self.pageHeightPoints = pageHeightPoints
            self.pageWidthInches = pageWidthInches
            self.pageHeightInches = pageHeightInches
            self.isEncrypted = isEncrypted
            self.isLocked = isLocked
            self.filePath = filePath
        }
    }

    public enum RenderError: Error, LocalizedError {
        case notPDF(String)
        case loadFailed(String)
        case pageOutOfRange(requested: Int, total: Int)
        case renderFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notPDF(let path): "文件不是 PDF: \(path)"
            case .loadFailed(let path): "无法加载 PDF: \(path)"
            case .pageOutOfRange(let requested, let total): "页码 \(requested) 超出范围，文档共 \(total) 页"
            case .renderFailed(let reason): "渲染失败: \(reason)"
            }
        }
    }

    /// 加载 PDF 文档
    public static func loadDocument(from url: URL) throws -> PDFDocument {
        guard url.pathExtension.lowercased() == "pdf" else {
            throw RenderError.notPDF(url.path)
        }
        guard let doc = PDFDocument(url: url) else {
            throw RenderError.loadFailed(url.path)
        }
        return doc
    }

    /// 获取 PDF 元数据
    public static func getInfo(from path: String, contextFolder: String?) throws -> PageInfo {
        let absolutePath: String
        if let folder = contextFolder {
            absolutePath = PathSecurity.resolvePath(path, relativeTo: folder)
            guard PathSecurity.validatePath(absolutePath, allowedBase: folder) else {
                throw RenderError.loadFailed("路径安全校验失败: \(absolutePath)")
            }
        } else {
            absolutePath = path
        }
        let url: URL = URL(fileURLWithPath: absolutePath)
        let doc = try loadDocument(from: url)

        var width: Double = 0
        var height: Double = 0
        if let firstPage = doc.page(at: 0) {
            let bounds = firstPage.bounds(for: .mediaBox)
            width = bounds.width
            height = bounds.height
        }

        return PageInfo(
            pageCount: doc.pageCount,
            pageWidthPoints: width,
            pageHeightPoints: height,
            pageWidthInches: width / 72.0,
            pageHeightInches: height / 72.0,
            isEncrypted: doc.isEncrypted,
            isLocked: doc.isLocked,
            filePath: absolutePath
        )
    }

    /// 渲染 PDF 指定页为 CGImage
    /// - Parameters:
    ///   - path: PDF 文件路径（相对或绝对）
    ///   - contextFolder: 工作目录（用于相对路径解析和路径校验）
    ///   - page: 页码（1-indexed，默认 1）
    ///   - dpi: 渲染分辨率（默认 300）
    /// - Returns: 渲染后的 CGImage
    public static func renderPage(
        from path: String,
        contextFolder: String?,
        page: Int = 1,
        dpi: Int = 300
    ) throws -> CGImage {
        let absolutePath: String = contextFolder.map { PathSecurity.resolvePath(path, relativeTo: $0) } ?? path
        if let base = contextFolder, !PathSecurity.validatePath(absolutePath, allowedBase: base) {
            throw RenderError.loadFailed("路径安全校验失败: \(absolutePath)")
        }
        let url: URL = URL(fileURLWithPath: absolutePath)
        let doc = try loadDocument(from: url)

        let pageIndex: Int = page - 1
        guard pageIndex >= 0, pageIndex < doc.pageCount else {
            throw RenderError.pageOutOfRange(requested: page, total: doc.pageCount)
        }
        guard let pdfPage = doc.page(at: pageIndex) else {
            throw RenderError.loadFailed("无法获取第 \(page) 页")
        }

        return try renderPDFPage(pdfPage, dpi: dpi)
    }

    /// 内部渲染逻辑
    private static func renderPDFPage(_ pdfPage: PDFPage, dpi: Int) throws -> CGImage {
        let pageRect = pdfPage.bounds(for: .mediaBox)
        let scale: CGFloat = CGFloat(dpi) / 72.0
        let width: Int = Int(pageRect.width * scale)
        let height: Int = Int(pageRect.height * scale)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let ctx: CGContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw RenderError.renderFailed("创建图形上下文失败")
        }

        ctx.setFillColor(CGColor.white)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        pdfPage.draw(with: .mediaBox, to: ctx)

        guard let cgImage = ctx.makeImage() else {
            throw RenderError.renderFailed("CGImage 创建失败")
        }
        return cgImage
    }
}
