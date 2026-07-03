import XCTest
import YunPatPlugins

final class MCPTransportTests: XCTestCase {

    // MARK: - InProcess 完整往返：register → handleRequest → response

    func test_inProcess_fullRoundTrip() async throws {
        let server = MCPServer()
        await server.registerTool(
            MCPToolDefinition(name: "echo", description: "Echo input")
        ) { args in
            "Echo: \(args["message"] ?? "")"
        }

        let transport = InProcessMCPTransport(server: server)
        let request = MCPRequest(method: "tools/list", id: 1)
        let responseData = try await transport.send(try JSONEncoder().encode(request))
        let responseStr = String(data: responseData, encoding: .utf8) ?? ""
        XCTAssertTrue(responseStr.contains("echo"), "Should list registered tools")
    }

    // MARK: - 多工具注册

    func test_multipleTools_listAll() async throws {
        let server = MCPServer()
        await server.registerTool(MCPToolDefinition(name: "a", description: "A tool")) { _ in "A" }
        await server.registerTool(MCPToolDefinition(name: "b", description: "B tool")) { _ in "B" }
        await server.registerTool(MCPToolDefinition(name: "c", description: "C tool")) { _ in "C" }

        let request = MCPRequest(method: "tools/list", id: 1)
        let transport = InProcessMCPTransport(server: server)
        let responseData = try await transport.send(try JSONEncoder().encode(request))
        let responseStr = String(data: responseData, encoding: .utf8) ?? ""
        for name in ["a", "b", "c"] {
            XCTAssertTrue(responseStr.contains(name), "Should contain tool '\(name)'")
        }
    }

    // MARK: - 工具不存在

    func test_toolNotFound_throwsError() async throws {
        let server = MCPServer()
        let request = MCPRequest(method: "tools/call", id: 1, params: ["name": "ghost"])
        let transport = InProcessMCPTransport(server: server)
        let responseData = try await transport.send(try JSONEncoder().encode(request))
        let response = try JSONDecoder().decode(MCPResponse.self, from: responseData)
        XCTAssertNotNil(response.error, "Should return error for unknown tool")
        XCTAssertTrue(response.error?.message.contains("not found") ?? false, "Got: \(response.error?.message ?? "")")
    }

    // MARK: - disconnect 清理连接

    func test_disconnect_safeOnMissingConnection() async {
        let client = MCPClient()
        await client.disconnect("non-existent")
        XCTAssertTrue(true)
    }

    // MARK: - handler 异常捕获

    func test_handlerError_propagated() async throws {
        let server = MCPServer()
        await server.registerTool(MCPToolDefinition(name: "boom", description: "Boom tool")) { _ in
            throw MCPError(message: "Handler exploded")
        }

        let request = MCPRequest(method: "tools/call", id: 1, params: ["name": "boom"])
        let transport = InProcessMCPTransport(server: server)
        let responseData = try await transport.send(try JSONEncoder().encode(request))
        let response = try JSONDecoder().decode(MCPResponse.self, from: responseData)
        XCTAssertNotNil(response.error, "Should propagate handler error")
    }

    // MARK: - StdioMCPTransport.parseContentLength

    func test_parseContentLength() {
        XCTAssertEqual(StdioMCPTransport.parseContentLength("Content-Length: 42\r\n\r\n"), 42)
        XCTAssertEqual(StdioMCPTransport.parseContentLength("Content-Length: 0\r\n\r\n"), 0)
        XCTAssertEqual(StdioMCPTransport.parseContentLength("no header"), 0)
    }

    // MARK: - HTTPMCPTransport.validate throws on non-200

    func test_httpTransport_validate() throws {
        let url = try XCTUnwrap(URL(string: "http://x"))
        let resp500 = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil))
        XCTAssertThrowsError(try HTTPMCPTransport.validate(resp500))
        let resp200 = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        XCTAssertNoThrow(try HTTPMCPTransport.validate(resp200))
    }
}
