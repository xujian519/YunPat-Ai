import AppKit
import Foundation

// MARK: - TestImageFactory

/// 程序化测试图像/PDF 生成器 — 对齐 Osaurus TestImageGenerator 设计（VisionToolsTests.swift:10-255）
///
/// 用法：
/// ```swift
/// try TestImageFactory.setup()
/// defer { TestImageFactory.cleanup() }
/// let url = try TestImageFactory.createTextImage(text: "Hello OCR")
/// ```
public enum TestImageFactory {

    public static let tempDir: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("yunpat-test-images-\(ProcessInfo.processInfo.processIdentifier)")
    }()

    public static func setup() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    public static func cleanup() {
        // 由系统在进程结束时清理
    }

    // MARK: - 图像生成

    /// 创建纯色图像
    public static func createColorImage(
        width: Int = 200, height: Int = 200, color: NSColor = .blue
    ) throws -> URL {
        let url = tempDir.appendingPathComponent("color_\(UUID().uuidString).png")
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        try saveImage(image, to: url)
        return url
    }

    /// 创建含文本的图像（供 OCR 测试使用）
    public static func createTextImage(text: String, fontSize: CGFloat = 48) throws -> URL {
        let url = tempDir.appendingPathComponent("text_\(UUID().uuidString).png")
        let size = NSSize(width: 400, height: 200)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.black
        ]
        let textSize = text.size(withAttributes: attrs)
        let point = NSPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        )
        text.draw(at: point, withAttributes: attrs)
        image.unlockFocus()

        try saveImage(image, to: url)
        return url
    }

    /// 创建含矩形轮廓的图像（供文档边界检测测试使用）
    public static func createRectangleImage() throws -> URL {
        let url = tempDir.appendingPathComponent("rect_\(UUID().uuidString).png")
        let size = NSSize(width: 400, height: 400)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        NSColor.black.setStroke()
        let rectPath = NSBezierPath(rect: NSRect(x: 50, y: 50, width: 300, height: 200))
        rectPath.lineWidth = 3
        rectPath.stroke()
        image.unlockFocus()

        try saveImage(image, to: url)
        return url
    }

    /// 创建简单人脸图形（供人脸检测测试使用）
    public static func createFaceImage() throws -> URL {
        let url = tempDir.appendingPathComponent("face_\(UUID().uuidString).png")
        let size = NSSize(width: 300, height: 300)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        // 脸部椭圆
        NSColor(calibratedRed: 0.95, green: 0.8, blue: 0.7, alpha: 1.0).setFill()
        let faceRect = NSRect(x: 75, y: 50, width: 150, height: 200)
        NSBezierPath(ovalIn: faceRect).fill()

        // 眼睛
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 105, y: 160, width: 30, height: 20)).fill()
        NSBezierPath(ovalIn: NSRect(x: 165, y: 160, width: 30, height: 20)).fill()

        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 115, y: 165, width: 10, height: 10)).fill()
        NSBezierPath(ovalIn: NSRect(x: 175, y: 165, width: 10, height: 10)).fill()

        // 鼻子
        NSColor.darkGray.setStroke()
        let nosePath = NSBezierPath()
        nosePath.move(to: NSPoint(x: 150, y: 150))
        nosePath.line(to: NSPoint(x: 145, y: 120))
        nosePath.line(to: NSPoint(x: 155, y: 120))
        nosePath.stroke()

        // 嘴巴
        NSColor.red.setStroke()
        let mouthPath = NSBezierPath()
        mouthPath.move(to: NSPoint(x: 120, y: 90))
        mouthPath.curve(
            to: NSPoint(x: 180, y: 90),
            controlPoint1: NSPoint(x: 140, y: 70),
            controlPoint2: NSPoint(x: 160, y: 70))
        mouthPath.lineWidth = 2
        mouthPath.stroke()

        image.unlockFocus()
        try saveImage(image, to: url)
        return url
    }

    /// 创建简单场景图像（供显著性检测测试使用）
    public static func createSceneImage() throws -> URL {
        let url = tempDir.appendingPathComponent("scene_\(UUID().uuidString).png")
        let size = NSSize(width: 400, height: 400)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.lightGray.setFill()
        NSRect(origin: .zero, size: size).fill()

        NSColor.red.setFill()
        NSBezierPath(ovalIn: NSRect(x: 150, y: 150, width: 100, height: 100)).fill()
        image.unlockFocus()

        try saveImage(image, to: url)
        return url
    }

    /// 创建地平线图像（供地平线检测测试使用）
    public static func createHorizonImage() throws -> URL {
        let url = tempDir.appendingPathComponent("horizon_\(UUID().uuidString).png")
        let size = NSSize(width: 400, height: 300)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.cyan.setFill()
        NSRect(x: 0, y: 150, width: 400, height: 150).fill()
        NSColor.green.setFill()
        NSRect(x: 0, y: 0, width: 400, height: 150).fill()
        image.unlockFocus()

        try saveImage(image, to: url)
        return url
    }

    // MARK: - PDF 生成

    /// 创建含文本的 PDF（供 OCR/PDF 测试使用）
    public static func createTextPDF(text: String, pages: Int = 1) throws -> URL {
        let url = tempDir.appendingPathComponent("pdf_\(UUID().uuidString).pdf")
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

        guard let ctx = CGContext(url as CFURL, mediaBox: nil, nil) else {
            throw NSError(
                domain: "TestImageFactory", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "CGContext 创建失败"])
        }

        for pageIndex in 1...pages {
            var box: CGRect = pageRect
            ctx.beginPage(mediaBox: &box)
            ctx.setFillColor(CGColor.white)
            ctx.fill(pageRect)

            let pageText: String = pages > 1 ? "\(text) - Page \(pageIndex)" : text
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 48),
                .foregroundColor: NSColor.black
            ]
            let attrStr = NSAttributedString(string: pageText, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attrStr)
            ctx.textPosition = CGPoint(x: 72, y: pageRect.height - 100)
            CTLineDraw(line, ctx)

            ctx.endPage()
        }
        ctx.closePDF()
        return url
    }

    // MARK: - Internal

    private static func saveImage(_ image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "TestImageFactory", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "PNG 编码失败"])
        }
        try pngData.write(to: url)
    }
}
