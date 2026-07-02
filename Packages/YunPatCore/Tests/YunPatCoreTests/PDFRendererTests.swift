import XCTest

@testable import YunPatCore

final class PDFRendererTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfrenderer-tests-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func createTestPDF(text: String, pages: Int = 1) throws -> URL {
        let url = tempDir.appendingPathComponent("test_\(UUID().uuidString).pdf")
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

        guard let ctx = CGContext(url as CFURL, mediaBox: nil, nil) else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "CGContext 失败"])
        }

        for path in 1...pages {
            var box: CGRect = pageRect
            ctx.beginPage(mediaBox: &box)
            ctx.setFillColor(CGColor.white)
            ctx.fill(pageRect)

            let pageText: String = pages > 1 ? "\(text) - Page \(path)" : text
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

    private func createNonPDF() throws -> URL {
        let url = tempDir.appendingPathComponent("not_a_pdf.txt")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - getInfo

    func testGetInfo_singlePage() throws {
        let url = try createTestPDF(text: "Hello PDF")
        let info = try PDFRenderer.getInfo(from: url.path, contextFolder: nil)

        XCTAssertEqual(info.pageCount, 1)
        XCTAssertEqual(info.pageWidthPoints, 612)
        XCTAssertEqual(info.pageHeightPoints, 792)
        XCTAssertEqual(info.pageWidthInches, 612 / 72.0)
        XCTAssertEqual(info.pageHeightInches, 792 / 72.0)
        XCTAssertFalse(info.isEncrypted)
        XCTAssertFalse(info.isLocked)
    }

    func testGetInfo_multiPage() throws {
        let url = try createTestPDF(text: "Multi Page", pages: 5)
        let info = try PDFRenderer.getInfo(from: url.path, contextFolder: nil)

        XCTAssertEqual(info.pageCount, 5)
    }

    func testGetInfo_notPDF_throws() throws {
        let url = try createNonPDF()
        XCTAssertThrowsError(try PDFRenderer.getInfo(from: url.path, contextFolder: nil)) { error in
            guard let renderError = error as? PDFRenderer.RenderError else {
                XCTFail("wrong error type")
                return
            }
            if case .notPDF = renderError {
            } else {
                XCTFail("expected notPDF, got \(renderError)")
            }
        }
    }

    // MARK: - renderPage

    func testRenderPage_defaultDPI() throws {
        let url = try createTestPDF(text: "Render Test")
        let cgImage = try PDFRenderer.renderPage(from: url.path, contextFolder: nil, page: 1, dpi: 300)

        // Letter size: 8.5×11 inches at 300 DPI
        XCTAssertEqual(cgImage.width, Int(612 * 300 / 72))
        XCTAssertEqual(cgImage.height, Int(792 * 300 / 72))
    }

    func testRenderPage_customDPI() throws {
        let url = try createTestPDF(text: "Low Res")
        let cgImage = try PDFRenderer.renderPage(from: url.path, contextFolder: nil, page: 1, dpi: 72)

        // 72 DPI → 1 point = 1 pixel
        XCTAssertEqual(cgImage.width, 612)
        XCTAssertEqual(cgImage.height, 792)
    }

    func testRenderPage_pageSelection() throws {
        let url = try createTestPDF(text: "Multi", pages: 3)
        // Page 2 should render without error
        let cgImage = try PDFRenderer.renderPage(from: url.path, contextFolder: nil, page: 2, dpi: 72)
        XCTAssertEqual(cgImage.width, 612)
    }

    func testRenderPage_outOfRange_throws() throws {
        let url = try createTestPDF(text: "Single", pages: 1)
        XCTAssertThrowsError(try PDFRenderer.renderPage(from: url.path, contextFolder: nil, page: 99, dpi: 72)) { error in
            guard let renderError = error as? PDFRenderer.RenderError else {
                XCTFail("wrong error type")
                return
            }
            if case .pageOutOfRange(let requested, let total) = renderError {
                XCTAssertEqual(requested, 99)
                XCTAssertEqual(total, 1)
            } else {
                XCTFail("expected pageOutOfRange")
            }
        }
    }

    func testRenderPage_invalidPath_throws() throws {
        XCTAssertThrowsError(try PDFRenderer.renderPage(from: "/nonexistent/test.pdf", contextFolder: nil))
    }

    // MARK: - path security integration

    func testGetInfo_withContextFolder() throws {
        let url = try createTestPDF(text: "Context Test")
        // use tempDir as context folder, path relative to it
        let info = try PDFRenderer.getInfo(from: url.lastPathComponent, contextFolder: tempDir.path)
        XCTAssertEqual(info.pageCount, 1)
    }

    func testRenderPage_traversalRejected() throws {
        let url = try createTestPDF(text: "Safe")
        // create path that traverses out of contextFolder
        let traversalPath: String = "../\(tempDir.lastPathComponent)/\(url.lastPathComponent)"
        XCTAssertThrowsError(
            try PDFRenderer.renderPage(
                from: traversalPath,
                contextFolder: tempDir.appendingPathComponent("sub").path,
                page: 1, dpi: 72
            ))
    }

    // MARK: - RenderError descriptions

    func testRenderErrorDescriptions() {
        XCTAssertEqual(
            PDFRenderer.RenderError.notPDF("/tmp/f.txt").errorDescription,
            "文件不是 PDF: /tmp/f.txt"
        )
        XCTAssertEqual(
            PDFRenderer.RenderError.pageOutOfRange(requested: 5, total: 3).errorDescription,
            "页码 5 超出范围，文档共 3 页"
        )
    }
}
