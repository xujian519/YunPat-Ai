import Foundation

public struct MCPRequest: Codable, Sendable {
    public let jsonrpc: String; public let id: Int; public let method: String; public let params: [String: String]?
    public init(method: String, id: Int = 1, params: [String: String]? = nil) { self.jsonrpc = "2.0"; self.id = id; self.method = method; self.params = params }
}

public struct MCPResponse: Codable, Sendable {
    public let jsonrpc: String; public let id: Int; public let result: String?; public let error: MCPError?
    public init(id: Int, result: String? = nil, error: MCPError? = nil) { self.jsonrpc = "2.0"; self.id = id; self.result = result; self.error = error }
}

public struct MCPError: Codable, Sendable, Error { public let code: Int; public let message: String; public init(code: Int = -1, message: String) { self.code = code; self.message = message } }
public struct MCPToolDefinition: Codable, Sendable { public let name: String; public let description: String; public let inputSchema: String; public init(name: String, description: String, inputSchema: String = "{}") { self.name = name; self.description = description; self.inputSchema = inputSchema } }
