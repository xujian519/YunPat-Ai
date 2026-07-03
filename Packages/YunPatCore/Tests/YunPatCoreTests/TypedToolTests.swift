import XCTest
import YunPatNetworking

@testable import YunPatCore

final class TypedToolTests: XCTestCase {

    // MARK: - TypedReadFileTool

    func test_readFile_readsContent() async throws {
        let dir: URL = FileManager.default.temporaryDirectory
        let file: URL = dir.appendingPathComponent("typed-test-\(UUID().uuidString).txt")
        try "line1\nline2\nline3\nline4\nline5".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let tool: TypedReadFileTool = TypedReadFileTool()
        let args: TypedReadFileTool.Args = TypedReadFileTool.Args(path: file.path, offset: 2, limit: 2)
        let response: ToolResponse = try await tool.execute(
            input: args,
            context: ToolContext(toolId: "", projectFolder: "", selectedProvider: .openai)
        )

        XCTAssertTrue(response.ok)
        let parsed: ToolResponse? = ToolResponse.tryParse(response.jsonString())
        XCTAssertNotNil(parsed)
    }

    func test_readFile_offsetLimit_correct() async throws {
        let dir: URL = FileManager.default.temporaryDirectory
        let file: URL = dir.appendingPathComponent("typed-limit-\(UUID().uuidString).txt")
        try "aaa\nbbb\nccc\nddd\neee".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let tool: TypedReadFileTool = TypedReadFileTool()
        let response: ToolResponse = try await tool.execute(
            input: TypedReadFileTool.Args(path: file.path, offset: 3, limit: 1),
            context: ToolContext(toolId: "", projectFolder: "", selectedProvider: .openai)
        )

        XCTAssertTrue(response.ok)
        let json: String = response.jsonString()
        XCTAssertTrue(json.contains("ccc"))
        XCTAssertFalse(json.contains("ddd"))
    }

    func test_readFile_fileNotFound() async throws {
        let tool: TypedReadFileTool = TypedReadFileTool()
        let response: ToolResponse = try await tool.execute(
            input: TypedReadFileTool.Args(path: "/nonexistent/\(UUID().uuidString)", offset: nil, limit: nil),
            context: ToolContext(toolId: "", projectFolder: "", selectedProvider: .openai)
        )

        XCTAssertFalse(response.ok)
        XCTAssertNotNil(response.error)
    }

    // MARK: - TypedPatentSearchTool

    func test_patentSearch_returnsResults() async throws {
        let tool: TypedPatentSearchTool = TypedPatentSearchTool { _, _ in
            [
                PatentSearchResultItem(patentNumber: "CN123", title: "Test", source: "google", relevanceScore: 0.9),
                PatentSearchResultItem(patentNumber: "CN456", title: "Other", source: "cnipa", relevanceScore: 0.7)
            ]
        }

        let response: ToolResponse = try await tool.execute(
            input: TypedPatentSearchTool.Args(query: "test", limit: 5),
            context: ToolContext(toolId: "", projectFolder: "", selectedProvider: .openai)
        )

        XCTAssertTrue(response.ok)
        let json: String = response.jsonString()
        XCTAssertTrue(json.contains("CN123"))
        XCTAssertTrue(json.contains("CN456"))
    }

    func test_patentSearch_emptyQuery_rejected() async throws {
        let tool: TypedPatentSearchTool = TypedPatentSearchTool { _, _ in [] }
        let response: ToolResponse = try await tool.execute(
            input: TypedPatentSearchTool.Args(query: "  ", limit: nil),
            context: ToolContext(toolId: "", projectFolder: "", selectedProvider: .openai)
        )

        XCTAssertFalse(response.ok)
    }

    // MARK: - TypedKnowledgeSearchTool

    func test_knowledgeSearch_returnsResults() async throws {
        let tool: TypedKnowledgeSearchTool = TypedKnowledgeSearchTool { _, _ in
            [KnowledgeSearchResultItem(content: "相关知识", score: 0.85, source: "local")]
        }

        let response: ToolResponse = try await tool.execute(
            input: TypedKnowledgeSearchTool.Args(query: "知识", limit: 3),
            context: ToolContext(toolId: "", projectFolder: "", selectedProvider: .openai)
        )

        XCTAssertTrue(response.ok)
        let json: String = response.jsonString()
        XCTAssertTrue(json.contains("相关知识"))
    }

    func test_knowledgeSearch_emptyQuery_rejected() async throws {
        let tool: TypedKnowledgeSearchTool = TypedKnowledgeSearchTool { _, _ in [] }
        let response: ToolResponse = try await tool.execute(
            input: TypedKnowledgeSearchTool.Args(query: "", limit: nil),
            context: ToolContext(toolId: "", projectFolder: "", selectedProvider: .openai)
        )

        XCTAssertFalse(response.ok)
    }

    // MARK: - TypedTool 框架

    func test_toolSpec_hasCorrectName() {
        let tool: TypedReadFileTool = TypedReadFileTool()
        XCTAssertEqual(tool.toolSpec.name, "typed_read_file")
        XCTAssertTrue(tool.toolSpec.parameters.contains("path"))
    }

    func test_toolSpec_patentSearch() {
        let tool: TypedPatentSearchTool = TypedPatentSearchTool { _, _ in [] }
        XCTAssertEqual(tool.toolSpec.name, "typed_patent_search")
        XCTAssertTrue(tool.toolSpec.parameters.contains("query"))
    }

    func test_handler_bridge_executes() async {
        let tool: TypedPatentSearchTool = TypedPatentSearchTool { _, _ in
            [PatentSearchResultItem(patentNumber: "X1", title: "Y", source: "s", relevanceScore: 1.0)]
        }

        let result: ToolHandlerResult = await tool.handler(
            "typed_patent_search",
            ["query": .string("hello")],
            ToolContext(toolId: "", projectFolder: "", selectedProvider: .openai)
        )

        guard case .handled(let text) = result else {
            XCTFail("Expected .handled")
            return
        }
        XCTAssertTrue(text.contains("X1"))
    }

    func test_handler_bridge_invalidArgs_returnsError() async {
        let tool: TypedReadFileTool = TypedReadFileTool()
        let result: ToolHandlerResult = await tool.handler(
            "typed_read_file",
            ["unexpected": .number(42)],
            ToolContext(toolId: "", projectFolder: "", selectedProvider: .openai)
        )

        guard case .handled(let text) = result else {
            XCTFail("Expected .handled")
            return
        }
        XCTAssertTrue(text.contains("\"ok\":false"), "Should return error for missing path")
    }

    // MARK: - TypedToolRegistry

    func test_registry_register() async {
        let registry: TypedToolRegistry = TypedToolRegistry()
        await registry.register(TypedReadFileTool())

        let names: [String] = await registry.registeredNames
        XCTAssertTrue(names.contains("typed_read_file"))
    }

    func test_registry_duplicateIgnored() async {
        let registry: TypedToolRegistry = TypedToolRegistry()
        await registry.register(TypedReadFileTool())
        await registry.register(TypedReadFileTool())

        let names: [String] = await registry.registeredNames
        XCTAssertEqual(names.filter { $0 == "typed_read_file" }.count, 1)
    }

    func test_registry_unregister() async {
        let registry: TypedToolRegistry = TypedToolRegistry()
        await registry.register(TypedReadFileTool())
        await registry.unregister("typed_read_file")

        let names: [String] = await registry.registeredNames
        XCTAssertFalse(names.contains("typed_read_file"))
    }

    func test_registry_multipleTools() async {
        let registry: TypedToolRegistry = TypedToolRegistry()
        await registry.register(TypedReadFileTool())
        await registry.register(TypedPatentSearchTool { _, _ in [] })
        await registry.register(TypedKnowledgeSearchTool { _, _ in [] })

        let names: [String] = await registry.registeredNames
        XCTAssertEqual(names.count, 3)
    }
}
