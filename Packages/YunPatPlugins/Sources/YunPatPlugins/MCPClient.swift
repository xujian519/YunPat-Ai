import Foundation

/// MCP 客户端 — 通过 MCPTransport 发送 JSON-RPC 请求
///
/// 支持工具（tools/list, tools/call）、资源（resources/list, resources/read）、
/// 提示词（prompts/list, prompts/get）等 MCP 协议方法。
public actor MCPClient {
    private var sessions: [String: MCPTransport] = [:]
    private var requestID: Int = 0

    public init() {}

    // MARK: - 连接管理

    /// 注册一个已启动的 MCP 传输连接
    public func register(serverID: String, transport: MCPTransport) {
        sessions[serverID] = transport
    }

    /// 断开指定服务器连接
    public func disconnect(_ serverID: String) async {
        try? await sessions[serverID]?.close()
        sessions[serverID] = nil
    }

    /// 断开所有连接
    public func disconnectAll() async {
        for (id, transport) in sessions {
            try? await transport.close()
            sessions.removeValue(forKey: id)
        }
    }

    /// 已注册的服务器 ID 列表
    public var connectedServers: [String] {
        Array(sessions.keys)
    }

    // MARK: - 工具

    /// 列出 MCP 服务器提供的所有工具
    public func listTools(serverID: String) async throws -> [MCPToolDefinition] {
        let response: MCPResponse = try await send(serverID: serverID, method: .toolsList)
        return extractResultArray(response)
    }

    /// 调用 MCP 服务器上的工具
    public func callTool(
        serverID: String,
        tool: String,
        arguments: MCPJSONValue = .object([:])
    ) async throws -> String {
        let params: MCPJSONValue = .object([
            "name": .string(tool),
            "arguments": arguments
        ])
        let response: MCPResponse = try await send(serverID: serverID, method: .toolsCall, params: params)
        guard let result = response.result else {
            throw MCPError(message: "Empty result from tools/call")
        }
        return result.jsonString()
    }

    // MARK: - 资源

    /// 列出 MCP 服务器提供的所有资源
    public func listResources(serverID: String) async throws -> [MCPResource] {
        let response: MCPResponse = try await send(serverID: serverID, method: .resourcesList)
        return extractResultArray(response)
    }

    /// 读取指定 MCP 资源
    public func readResource(serverID: String, uri: String) async throws -> MCPResourceContents {
        let params: MCPJSONValue = .object(["uri": .string(uri)])
        let response: MCPResponse = try await send(serverID: serverID, method: .resourcesRead, params: params)
        guard let result = response.result,
              let obj = result.objectValue,
              let contentsData = obj["contents"]
        else {
            throw MCPError(message: "Invalid resources/read response")
        }
        // contents 可能是数组，取第一个
        let contents: [MCPResourceContents]
        if case .array(let arr) = contentsData {
            contents = arr.compactMap { val in
                guard let data = try? JSONEncoder().encode(val),
                      let item = try? JSONDecoder().decode(MCPResourceContents.self, from: data)
                else { return nil }
                return item
            }
        } else {
            contents = []
        }
        return contents.first ?? MCPResourceContents(uri: uri)
    }

    // MARK: - 提示词

    /// 列出 MCP 服务器提供的所有提示词
    public func listPrompts(serverID: String) async throws -> [MCPPrompt] {
        let response: MCPResponse = try await send(serverID: serverID, method: .promptsList)
        return extractResultArray(response)
    }

    /// 获取指定提示词内容
    public func getPrompt(
        serverID: String, name: String, arguments: [String: String] = [:]
    ) async throws -> [MCPPromptMessage] {
        var paramsObj: [String: MCPJSONValue] = ["name": .string(name)]
        if !arguments.isEmpty {
            paramsObj["arguments"] = .object(arguments.mapValues { .string($0) })
        }
        let response: MCPResponse = try await send(
            serverID: serverID, method: .promptsGet,
            params: .object(paramsObj)
        )
        guard let result = response.result,
              let obj = result.objectValue,
              let messagesData = obj["messages"]
        else {
            throw MCPError(message: "Invalid prompts/get response")
        }
        if case .array(let arr) = messagesData {
            return arr.compactMap { val in
                guard let data = try? JSONEncoder().encode(val),
                      let msg = try? JSONDecoder().decode(MCPPromptMessage.self, from: data)
                else { return nil }
                return msg
            }
        }
        return []
    }

    // MARK: - Ping

    /// 检查服务器连接是否正常
    public func ping(serverID: String) async -> Bool {
        do {
            let _: MCPResponse = try await send(serverID: serverID, method: .ping)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Internal

    private func nextID() -> Int {
        requestID += 1
        return requestID
    }

    private func send(serverID: String, method: MCPMethod, params: MCPJSONValue? = nil) async throws -> MCPResponse {
        guard let transport = sessions[serverID] else {
            throw MCPError(message: "Not connected to server '\(serverID)'")
        }
        let request = MCPRequest(method: method.rawValue, id: nextID(), params: params)
        let payload = try JSONEncoder().encode(request)
        let responseData: Data = try await transport.send(payload)
        return try JSONDecoder().decode(MCPResponse.self, from: responseData)
    }

    private func extractResultArray<T: Codable>(_ response: MCPResponse) -> [T] {
        guard let result = response.result,
              let obj = result.objectValue,
              let items = obj[Self.listKey(for: T.self)]
        else { return [] }
        if case .array(let arr) = items {
            return arr.compactMap { val in
                guard let data = try? JSONEncoder().encode(val),
                      let item = try? JSONDecoder().decode(T.self, from: data)
                else { return nil }
                return item
            }
        }
        return []
    }

    private static func listKey<T>(for type: T.Type) -> String {
        if type == MCPToolDefinition.self { return "tools" }
        if type == MCPResource.self { return "resources" }
        if type == MCPPrompt.self { return "prompts" }
        return "items"
    }
}
