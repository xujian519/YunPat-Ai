import Foundation
import XCTest
@testable import YunPatCore

final class MemoryAuditServiceTests: XCTestCase {
    private var service: MemoryAuditService!
    private var store: MemoryStore!

    /// 每个 test 实例使用独立 UserDefaults suite，防止测试间数据泄漏
    private let suiteName = "com.yunpat.test.MemoryAuditService.\(UUID().uuidString)"

    override func setUp() async throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create UserDefaults suite: \(suiteName)")
            return
        }
        store = MemoryStore(defaults: defaults)
        service = MemoryAuditService(store: store)
    }

    override func tearDown() {
        service = nil
        store = nil
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Tests

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
        let ctx = CaseContext(caseId: "C002", inventionPoints: ["原始特征"])
        try await store.saveCaseContext(ctx)

        let entries = await service.listEntries(caseId: "C002")
        let first = try XCTUnwrap(entries.first)
        var entry = first
        entry.content = "修改后特征"
        try await service.updateEntry(entry, caseId: "C002")

        let updated = await service.entry(id: entry.id, caseId: "C002")
        XCTAssertEqual(updated?.content, "修改后特征")
        XCTAssertEqual(updated?.source, .manualEdit)
    }

    func test_deleteEntry_removesFromContext() async throws {
        let ctx = CaseContext(caseId: "C003", inventionPoints: ["可删除特征"])
        try await store.saveCaseContext(ctx)

        let entries = await service.listEntries(caseId: "C003")
        let entry = try XCTUnwrap(entries.first)
        try await service.deleteEntry(entry, caseId: "C003")

        let remaining = await service.listEntries(caseId: "C003")
        XCTAssertTrue(remaining.isEmpty)
    }

    func test_deletePinnedEntry_throws() async throws {
        let ctx = CaseContext(caseId: "C004", inventionPoints: ["固定特征"])
        try await store.saveCaseContext(ctx)

        let entries = await service.listEntries(caseId: "C004")
        let entry = try XCTUnwrap(entries.first)
        try await service.togglePin(entry, caseId: "C004")

        let pinned = await service.entry(id: entry.id, caseId: "C004")
        let unwrapped = try XCTUnwrap(pinned)
        await XCTAssertThrowsErrorAsync(try await service.deleteEntry(unwrapped, caseId: "C004"))
    }

    func test_legacyCaseContextStringArray_migratesToAuditableEntries() async throws {
        let legacyJSON = """
        {
            "caseId": "LEGACY",
            "technicalField": "旧版领域",
            "inventionPoints": ["旧点1", "旧点2"],
            "keyReferences": [],
            "openIssues": []
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let ctx = try decoder.decode(CaseContext.self, from: legacyJSON)

        XCTAssertEqual(ctx.technicalField, "旧版领域")
        XCTAssertEqual(ctx.technicalFieldEntry?.content, "旧版领域")
        XCTAssertEqual(ctx.inventionPointEntries.count, 2)
        XCTAssertEqual(ctx.inventionPoints, ["旧点1", "旧点2"])
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
            try await expression()
            XCTFail("Expected error but no error was thrown", file: file, line: line)
        } catch {
            // expected
        }
    }
}
