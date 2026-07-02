import Foundation

public actor MCPServer {
    private var toolRegistry: [String: (MCPToolDefinition, (([String: String]) async throws -> String))] = [:]
    public init() {}

    public func registerTool(_ tool: MCPToolDefinition, handler: @escaping (([String: String]) async throws -> String)) { toolRegistry[tool.name] = (tool, handler) }

    public func start() async throws {
        let stdin = FileHandle.standardInput
        let stdout = FileHandle.standardOutput
        while true {
            guard
                let line = String(data: stdin.availableData, encoding: .utf8)?.trimmingCharacters(
                    in: .whitespacesAndNewlines), !line.isEmpty
            else { continue }
            guard let data = line.data(using: .utf8),
                let request = try? JSONDecoder().decode(MCPRequest.self, from: data)
            else { continue }
            let response: MCPResponse
            switch request.method {
            case "tools/list":
                let tools = Array(toolRegistry.values).map { $0.0 }
                response = MCPResponse(
                    id: request.id, result: String(data: (try? JSONEncoder().encode(tools)) ?? Data(), encoding: .utf8))
            case "tools/call":
                if let toolName = request.params?["name"], let (_, handler) = toolRegistry[toolName] {
                    response = MCPResponse(id: request.id, result: try await handler(request.params ?? [:]))
                } else {
                    response = MCPResponse(id: request.id, error: MCPError(message: "Tool not found"))
                }
            default: response = MCPResponse(id: request.id, error: MCPError(code: -32601, message: "Method not found"))
            }
            let responseData = try JSONEncoder().encode(response)
            stdout.write(responseData)
            stdout.write("\n".data(using: .utf8)!)
        }
    }
}
