import XCTest
@testable import YunPatCore

final class DocumentAdapterTests: XCTestCase {

    private var registry: DocumentAdapterRegistry!

    override func setUp() async throws {
        registry = DocumentAdapterRegistry()
        await registry.register(PlainTextDocumentAdapter())
        await registry.register(CSVDocumentAdapter())
    }

    // MARK: - PlainText

    func testPlainText_simpleText() async throws {
        let data = "Hello, 世界".data(using: .utf8)!
        let content = try await registry.parse(data: data, fileName: "test.txt")
        XCTAssertTrue(content.text.contains("Hello"))
        XCTAssertGreaterThan(content.metadata.fileSize, 0)
    }

    func testPlainText_markdownSections() async throws {
        let md = """
        # Title
        Content here.
        ## Subtitle
        More content.
        """
        let data = md.data(using: .utf8)!
        let content = try await registry.parse(data: data, fileName: "doc.md")
        XCTAssertEqual(content.sections.count, 2)
        XCTAssertEqual(content.sections[0].heading, "Title")
        XCTAssertEqual(content.sections[1].heading, "Subtitle")
    }

    func testPlainText_largeFile_truncation() async throws {
        let large = String(repeating: "A", count: 200_000)
        let data = large.data(using: .utf8)!
        let content = try await registry.parse(data: data, fileName: "big.txt")
        XCTAssertTrue(content.text.count < 150_000, "Should truncate large file")
        XCTAssertTrue(content.text.contains("文件过大"), "Should note truncation")
    }

    func testPlainText_unsupportedExtension() async throws {
        let data = "test".data(using: .utf8)!
        do {
            _ = try await registry.parse(data: data, fileName: "file.xyz")
            XCTFail("Should throw")
        } catch let error as DocumentAdapterError {
            if case .unsupportedFormat = error { /* expected */ } else { XCTFail("Wrong error") }
        } catch {
            XCTFail("Wrong error type")
        }
    }

    // MARK: - CSV

    func testCSV_basicParsing() async throws {
        let csv = "name,age\nAlice,30\nBob,25\n"
        let data = csv.data(using: .utf8)!
        let content = try await registry.parse(data: data, fileName: "data.csv")
        XCTAssertTrue(content.text.contains("Alice"))
        XCTAssertTrue(content.text.contains("Bob"))
        XCTAssertTrue(content.text.contains("30"))
    }

    func testCSV_quotedFields() async throws {
        let csv = #""name","age"\n"Alice,Wang",30\n"Bob",25\n"#
        let data = csv.data(using: .utf8)!
        let content = try await registry.parse(data: data, fileName: "data.csv")
        XCTAssertTrue(content.text.contains("Alice"))
        XCTAssertTrue(content.text.contains("Wang"))
    }

    func testCSV_tsvFormat() async throws {
        let tsv = "name\tage\nAlice\t30\nBob\t25\n"
        let data = tsv.data(using: .utf8)!
        let content = try await registry.parse(data: data, fileName: "data.tsv")
        XCTAssertTrue(content.text.contains("Alice"))
    }

    // MARK: - Registry

    func testRegistry_autoSelectAdapter() async throws {
        let txtData = "plain text".data(using: .utf8)!
        let txtContent = try await registry.parse(data: txtData, fileName: "test.txt")
        XCTAssertTrue(txtContent.text.contains("plain text"))

        let csvData = "a,b\n1,2\n".data(using: .utf8)!
        let csvContent = try await registry.parse(data: csvData, fileName: "test.csv")
        XCTAssertTrue(csvContent.text.contains("1"))
    }

    func testRegistry_unsupportedFormat() async throws {
        let data = "test".data(using: .utf8)!
        do {
            _ = try await registry.parse(data: data, fileName: "file.xyz")
            XCTFail("Should throw")
        } catch DocumentAdapterError.unsupportedFormat {
            // expected
        }
    }

    func testRegistry_registeredExtensions() async throws {
        let exts = await registry.registeredExtensions
        XCTAssertTrue(exts.contains("txt"))
        XCTAssertTrue(exts.contains("csv"))
        XCTAssertTrue(exts.contains("tsv"))
        XCTAssertTrue(exts.contains("md"))
    }

    // MARK: - AdapterProvider

    func testDefaultProvider_createsRegistry() async throws {
        let reg = await DocumentAdapterProvider.createDefaultRegistry()
        let exts = await reg.registeredExtensions
        XCTAssertTrue(exts.contains("pdf"), "Should have PDF adapter")
        XCTAssertTrue(exts.contains("docx"), "Should have Office adapter")
        XCTAssertTrue(exts.contains("csv"), "Should have CSV adapter")
    }
}
