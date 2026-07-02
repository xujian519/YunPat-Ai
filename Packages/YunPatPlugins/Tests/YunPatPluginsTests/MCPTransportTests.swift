import XCTest
import YunPatPlugins

final class MCPTransportTests: XCTestCase {

    // MARK: - InProcess 完整往返：connect → listTools → callTool

    func test_inProcess_fullRoundTrip() async throws {
        let server = MCPServer()
        await server.registerTool(
            MCPToolDefinition(name: "echo", description: "Echo input")
        ) { args in
            "Echo: \(args["message"] ?? "")"
        }

        let client = MCPClient()
        try await client.connectInProcess(serverID: "test", server: server)

        let tools: [MCPToolDefinition] = try await client.listTools(serverID: "test")
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0].name, "echo")
        XCTAssertEqual(tools[0].description, "Echo input")

        let result: String = try await client.callTool(serverID: "test", tool: "echo", arguments: ["message": "hello"])
        XCTAssertEqual(result, "Echo: hello")

        await client.disconnect("test")
    }

    // MARK: - 多工具注册

    func test_multipleTools_listAll() async throws {
        let server = MCPServer()
        await server.registerTool(MCPToolDefinition(name: "a")) { _ in "A" }
        await server.registerTool(MCPToolDefinition(name: "b")) { _ in "B" }
        await server.registerTool(MCPToolDefinition(name: "c")) { _ in "C" }

        let client = MCPClient()
        try await client.connectInProcess(serverID: "multi", server: server)

        let tools: [MCPToolDefinition] = try await client.listTools(serverID: "multi")
        XCTAssertEqual(Set(tools.map(\.name)), ["a", "b", "c"])
    }

    // MARK: - 工具不存在

    func test_toolNotFound_throwsError() async throws {
        let server = MCPServer()
        let client = MCPClient()
        try await client.connectInProcess(serverID: "err", server: server)

        do {
            _ = try await client.callTool(serverID: "err", tool: "ghost", arguments: [:])
            XCTFail("Should throw")
        } catch let err as MCPError {
            XCTAssertTrue(err.message.contains("Tool not found"), "Got: \(err.message)")
        }
    }

    // MARK: - disconnect 清理连接

    func test_disconnect_clearsConnection() async throws {
        let server = MCPServer()
        await server.registerTool(MCPToolDefinition(name: "x")) { _ in "X" }

        let client = MCPClient()
        try await client.connectInProcess(serverID: "dc", server: server)
        _ = try await client.listTools(serverID: "dc")

        await client.disconnect("dc")

        do {
            _ = try await client.listTools(serverID: "dc")
            XCTFail("Should throw after disconnect")
        } catch {
            // 期望
        }
    }

    // MARK: - 自定义 transport 注入

    func test_customTransport_injection() async throws {
        let transport = MockTransport()
        let client = MCPClient()
        try await client.connect(serverID: "custom", transport: transport)

        let tools: [MCPToolDefinition] = try await client.listTools(serverID: "custom")
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0].name, "mock_tool")

        XCTAssertGreaterThanOrEqual(transport.requestCount, 2)
    }

    // MARK: - handler 异常捕获

    func test_handlerError_propagated() async throws {
        let server = MCPServer()
        await server.registerTool(MCPToolDefinition(name: "boom")) { _ in
            throw MCPError(message: "Handler exploded")
        }

        let client = MCPClient()
        try await client.connectInProcess(serverID: "boom-test", server: server)

        do {
            _ = try await client.callTool(serverID: "boom-test", tool: "boom", arguments: [:])
            XCTFail("Should throw")
        } catch let err as MCPError {
            XCTAssertTrue(err.message.contains("Handler exploded"), "Got: \(err.message)")
        }
    }

    // MARK: - disconnectAll

    func test_disconnectAll_clearsAll() async throws {
        let server1 = MCPServer()
        await server1.registerTool(MCPToolDefinition(name: "a")) { _ in "A" }
        let server2 = MCPServer()
        await server2.registerTool(MCPToolDefinition(name: "b")) { _ in "B" }

        let client = MCPClient()
        try await client.connectInProcess(serverID: "s1", server: server1)
        try await client.connectInProcess(serverID: "s2", server: server2)

        _ = try await client.listTools(serverID: "s1")
        _ = try await client.listTools(serverID: "s2")

        await client.disconnectAll()

        do {
            _ = try await client.listTools(serverID: "s1")
            XCTFail("Should throw")
        } catch { /* 期望 */  }
    }

    // MARK: - StdioMCPTransport.parseContentLength

    func test_parseContentLength() {
        XCTAssertEqual(StdioMCPTransport.parseContentLength("Content-Length: 42\r\n\r\n"), 42)
        XCTAssertEqual(StdioMCPTransport.parseContentLength("Content-Length: 0\r\n\r\n"), 0)
        XCTAssertEqual(StdioMCPTransport.parseContentLength("no header"), 0)
    }

    // MARK: - HTTPMCPTransport.validate

    func test_httpTransport_validate_throwsOnNon200() {
        let url = XCTUnwrap(URL(string: "http://x"))
        let resp = XCTUnwrap(HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil))
        XCTAssertThrowsError(try HTTPMCPTransport.validate(resp))
    }

    func test_httpTransport_validate_passesOn200() {
        let url = XCTUnwrap(URL(string: "http://x"))
        let resp = XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        XCTAssertNoThrow(try HTTPMCPTransport.validate(resp))
    }
}

// MARK: - Mock Transport（测试用自定义传输）

private final class MockTransport: MCPTransport, @unchecked Sendable {
    private(set) var requestCount: Int = 0

    func send(_ payload: Data) async throws -> Data {
        requestCount += 1
        guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let method = json["method"] as? String,
            let id = json["id"] as? Int
        else {
            throw MCPError(message: "Invalid request")
        }

        switch method {
        case "initialize":
            return try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0", "id": id,
                "result": ["protocolVersion": "2025-03-26", "capabilities": [:]]
            ])
        case "tools/list":
            return try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0", "id": id,
                "result": ["tools": [["name": "mock_tool", "description": "Mock"]]]
            ])
        default:
            return try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0", "id": id,
                "error": ["code": -32601, "message": "Not implemented"]
            ])
        }
    }

    func close() async throws {}
}
