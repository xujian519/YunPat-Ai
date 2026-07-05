import Foundation
import XCTest
@testable import YunPatCore

final class MemoryAuditServiceTests: XCTestCase {
    private var service: MemoryAuditService!
    private var store: MemoryStore!

    override func setUp() async throws {
        store = MemoryStore()
        service = MemoryAuditService(store: store)
    }

    override func tearDown() {
        service = nil
        store = nil
    }

    func test_listEntries_emptyStore_returnsGlobalOnly() async throws {
        let entries = await service.listEntries(caseId: nil)
        XCTAssertTrue(entries.isEmpty)
    }

    func test_listEntries_caseContext_returnsEntries() async throws {
        var ctx = CaseContext(
            caseId: "C001",
            technicalField: "人工智能",
            inventionPoints: ["特征A", "特征B"],
            keyReferences: ["对比文件1"]
        )
        ctx.openIssues = ["待解决问题X"]
        try await store.saveCaseContext(ctx)

        let entries = await service.listEntries(caseId: "C001")
        XCTAssertEqual(entries.count, 5)
        XCTAssertTrue(entries.contains { $0.content == "人工智能" })
        XCTAssertTrue(entries.contains { $0.content == "特征A" })
        XCTAssertTrue(entries.contains { $0.content == "待解决问题X" })
    }

    func test_updateEntry_changesContentAndSource() async throws {
        var ctx = CaseContext(caseId: "C002", inventionPoints: ["原始特征"])
        try await store.saveCaseContext(ctx)

        var entry = await service.listEntries(caseId: "C002").first!
        entry.content = "修改后特征"
        try await service.updateEntry(entry, caseId: "C002")

        let updated = await service.entry(id: entry.id, caseId: "C002")
        XCTAssertEqual(updated?.content, "修改后特征")
        XCTAssertEqual(updated?.source, .manualEdit)
    }

    func test_deleteEntry_removesFromContext() async throws {
        var ctx = CaseContext(caseId: "C003", inventionPoints: ["可删除特征"])
        try await store.saveCaseContext(ctx)

        let entry = await service.listEntries(caseId: "C003").first!
        try await service.deleteEntry(entry, caseId: "C003")

        let entries = await service.listEntries(caseId: "C003")
        XCTAssertTrue(entries.isEmpty)
    }

    func test_deletePinnedEntry_throws() async throws {
        var ctx = CaseContext(caseId: "C004", inventionPoints: ["固定特征"])
        try await store.saveCaseContext(ctx)

        let entry = await service.listEntries(caseId: "C004").first!
        try await service.togglePin(entry, caseId: "C004")

        let pinned = await service.entry(id: entry.id, caseId: "C004")!
        await XCTAssertThrowsErrorAsync(try await service.deleteEntry(pinned, caseId: "C004"))
    }

    func test_legacyCaseContextStringArray_migratesToAuditableEntries() async throws {
        let legacyJSON = """
        {
            "caseId": "LEGACY",
            "technicalField": "旧技术",
            "inventionPoints": ["旧特征1", "旧特征2"],
            "keyReferences": [],
            "openIssues": [],
            "lastModified": 0
        }
        """.data(using: .utf8)!

        let ctx = try JSONDecoder().decode(CaseContext.self, from: legacyJSON)
        XCTAssertEqual(ctx.technicalField, "旧技术")
        XCTAssertEqual(ctx.inventionPointEntries.count, 2)
        XCTAssertEqual(ctx.inventionPointEntries.first?.source, .sessionFact)
        XCTAssertEqual(ctx.inventionPoints, ["旧特征1", "旧特征2"])
    }
}

extension XCTest {
    func XCTAssertThrowsErrorAsync(
        _ expression: @autoclosure () async throws -> Void,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            // expected
        }
    }
}
