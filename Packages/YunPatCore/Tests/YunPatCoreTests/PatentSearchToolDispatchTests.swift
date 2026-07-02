import Foundation
import XCTest

@testable import YunPatCore

/// SearchCommander + ToolDispatch 集成测试
///
/// 使用内存中的 WikiAdapter 与 Mock 检索后端，避免真实网络依赖。
final class PatentSearchToolDispatchTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempVault() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func makeCommander(wikiAdapter: WikiAdapter) -> SearchCommander {
        SearchCommander(wikiAdapter: wikiAdapter)
    }

    private func makeContext() -> ToolContext {
        ToolContext(toolId: "test", projectFolder: "", selectedProvider: .deepseek)
    }

    private func makeToolCall(name: String, args: [String: Any]) -> ToolCall {
        let stringArgs = args.reduce(into: [String: String]()) { result, pair in
            if let array = pair.value as? [String] {
                result[pair.key] = array.joined(separator: ",")
            } else {
                result[pair.key] = String(describing: pair.value)
            }
        }
        return ToolCall(id: UUID().uuidString, name: name, arguments: stringArgs)
    }

    // MARK: - patent_search

    func testPatentSearch_emptyQuery_returnsInvalidArgs() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let commander = makeCommander(wikiAdapter: WikiAdapter(vaultPath: vault))
        ToolDispatch.shared.configure(searchCommander: commander)

        let result = await ToolDispatch.executeCall(
            makeToolCall(name: "patent_search", args: ["query": ""]),
            ctx: makeContext()
        )

        let response = ToolResponse.tryParse(result.content)
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.ok, false)
        XCTAssertEqual(response?.error?.code, ToolErrorCode.invalidArgs.rawValue)
    }

    func testPatentSearch_localKBSource_returnsWikiResult() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        // 构造本地知识库内容
        let wikiDir = vault.appendingPathComponent("Wiki/专利实务")
        try FileManager.default.createDirectory(at: wikiDir, withIntermediateDirectories: true)
        try "人工智能专利撰写指南".write(to: wikiDir.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)

        let commander = makeCommander(wikiAdapter: WikiAdapter(vaultPath: vault))
        ToolDispatch.shared.configure(searchCommander: commander)

        let result = await ToolDispatch.executeCall(
            makeToolCall(
                name: "patent_search",
                args: [
                    "query": "人工智能",
                    "sources": "local_kb"
                ]),
            ctx: makeContext()
        )

        let response = ToolResponse.tryParse(result.content)
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.ok, true)

        guard case .object(let dict) = response?.data else {
            XCTFail("Expected object data")
            return
        }
        XCTAssertEqual(dict["query"], .string("人工智能"))
        guard case .array(let results) = dict["results"] else {
            XCTFail("Expected results array")
            return
        }
        XCTAssertEqual(results.count, 1)
    }

    func testPatentSearch_limit_trimsResults() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let wikiDir = vault.appendingPathComponent("Wiki/专利实务")
        try FileManager.default.createDirectory(at: wikiDir, withIntermediateDirectories: true)
        try "人工智能".write(to: wikiDir.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)

        let commander = makeCommander(wikiAdapter: WikiAdapter(vaultPath: vault))
        ToolDispatch.shared.configure(searchCommander: commander)

        let result = await ToolDispatch.executeCall(
            makeToolCall(
                name: "patent_search",
                args: [
                    "query": "人工智能",
                    "sources": "local_kb",
                    "limit": 1
                ]),
            ctx: makeContext()
        )

        let response = ToolResponse.tryParse(result.content)
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.ok, true)

        guard case .object(let dict) = response?.data else {
            XCTFail("Expected object data")
            return
        }
        guard case .array(let results) = dict["results"] else {
            XCTFail("Expected results array")
            return
        }
        XCTAssertEqual(results.count, 1)
    }

    func testPatentSearch_zeroLimit_returnsEmptyResults() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let wikiDir = vault.appendingPathComponent("Wiki/专利实务")
        try FileManager.default.createDirectory(at: wikiDir, withIntermediateDirectories: true)
        try "人工智能".write(to: wikiDir.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)

        let commander = makeCommander(wikiAdapter: WikiAdapter(vaultPath: vault))
        ToolDispatch.shared.configure(searchCommander: commander)

        let result = await ToolDispatch.executeCall(
            makeToolCall(
                name: "patent_search",
                args: [
                    "query": "人工智能",
                    "sources": "local_kb",
                    "limit": "0"
                ]),
            ctx: makeContext()
        )

        let response = ToolResponse.tryParse(result.content)
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.ok, false)
        XCTAssertEqual(response?.error?.code, ToolErrorCode.notFound.rawValue)
    }

    // MARK: - legal_status_query

    func testLegalStatusQuery_emptyNumber_returnsInvalidArgs() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let commander = makeCommander(wikiAdapter: WikiAdapter(vaultPath: vault))
        ToolDispatch.shared.configure(searchCommander: commander)

        let result = await ToolDispatch.executeCall(
            makeToolCall(name: "legal_status_query", args: ["patent_number": ""]),
            ctx: makeContext()
        )

        let response = ToolResponse.tryParse(result.content)
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.ok, false)
        XCTAssertEqual(response?.error?.code, ToolErrorCode.invalidArgs.rawValue)
    }

    func testLegalStatusQuery_invalidNumber_returnsNotFoundOrError() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let commander = makeCommander(wikiAdapter: WikiAdapter(vaultPath: vault))
        ToolDispatch.shared.configure(searchCommander: commander)

        let result = await ToolDispatch.executeCall(
            makeToolCall(name: "legal_status_query", args: ["patent_number": "INVALID-NO-12345"]),
            ctx: makeContext()
        )

        let response = ToolResponse.tryParse(result.content)
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.ok, false)
    }
}
