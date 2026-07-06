import Foundation
import YunPatCore

/// MCP 工具桥接 — 将 MCP 服务器暴露的工具注册到 ToolDispatch
///
/// 当 MCP 服务器通过 `tools/list` 提供工具列表时，
/// 桥接器自动为每个工具创建 ToolDispatch handler，
/// handler 内部通过 `MCPClient.callTool` 执行。
public actor MCPToolBridge {
    public static let shared: MCPToolBridge = MCPToolBridge()

    private let client: MCPClient
    private var registeredServers: Set<String> = []

    private init(client: MCPClient = MCPClient()) {
        self.client = client
    }

    /// 获取底层 MCP 客户端，用于手动注册 transport
    public var mcpClient: MCPClient { client }

    /// 注册 MCP 服务器并自动桥接其工具到 ToolDispatch
    public func registerServer(
        id: String,
        transport: MCPTransport,
        toolDispatch: ToolDispatch
    ) async throws {
        await client.register(serverID: id, transport: transport)

        // 获取工具列表
        let tools: [MCPToolDefinition]
        do {
            tools = try await client.listTools(serverID: id)
        } catch {
            // 初始化可能还没完成，尝试先 ping 再重试
            _ = try? await Task.sleep(nanoseconds: 500_000_000)
            tools = (try? await client.listTools(serverID: id)) ?? []
        }

        for tool in tools {
            let mcpName: String = tool.name
            let dispatchName: String = "mcp_\(id)_\(mcpName)"
            toolDispatch.register(
                name: dispatchName, description: tool.description,
                handler: { [client, id, mcpName] _, input, _ in
                    let args: MCPJSONValue = .object(input.mapValues(MCPJSONValue.fromJSONValue))
                    do {
                        let result: String = try await client.callTool(
                            serverID: id, tool: mcpName, arguments: args
                        )
                        return .handled(result)
                    } catch {
                        return .handled("MCP error: \(error.localizedDescription)")
                    }
                }
            )
        }
        registeredServers.insert(id)
    }

    /// 注销 MCP 服务器并从 ToolDispatch 移除其工具
    public func unregisterServer(id: String, toolDispatch: ToolDispatch) async {
        // 移除该服务器注册的所有工具
        for name in toolDispatch.registeredTools where name.hasPrefix("mcp_\(id)_") {
            toolDispatch.unregister(name: name)
        }
        await client.disconnect(id)
        registeredServers.remove(id)
    }

    /// 已注册的 MCP 服务器 ID 列表
    public var activeServers: [String] {
        Array(registeredServers)
    }
}

// MARK: - JSONValue → MCPJSONValue 转换

extension MCPJSONValue {
    static func fromJSONValue(_ value: JSONValue) -> MCPJSONValue {
        switch value {
        case .string(let str): return .string(str)
        case .number(let num): return .double(num)
        case .bool(let boolVal): return .bool(boolVal)
        case .null: return .null
        case .array(let arr): return .array(arr.map(fromJSONValue))
        case .object(let obj): return .object(obj.mapValues(fromJSONValue))
        }
    }
}
