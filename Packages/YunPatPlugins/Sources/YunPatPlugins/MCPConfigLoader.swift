import Foundation

/// MCP 服务器配置加载器 — 从 JSON 文件加载 MCP 服务器配置
///
/// 配置格式：
/// ```json
/// {
///   "mcpServers": {
///     "my-server": {
///       "command": "node",
///       "args": ["server.js"],
///       "env": { "KEY": "value" },
///       "disabled": false
///     }
///   }
/// }
/// ```
public struct MCPConfigLoader: Sendable {

    public struct MCPConfig: Codable, Sendable {
        public let mcpServers: [String: MCPServerConfig]?
    }

    public struct MCPServerConfig: Codable, Sendable {
        public let command: String
        public let args: [String]?
        public let env: [String: String]?
        public let disabled: Bool?

        public var isEnabled: Bool { !(disabled ?? false) }
    }

    public init() {}

    /// 从文件路径加载配置
    public func load(from path: String) throws -> MCPConfig {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(MCPConfig.self, from: data)
    }

    /// 创建 StdioMCPTransport 实例
    /// - Returns: (serverID, transport) 元组数组
    public func createTransports(from config: MCPConfig) -> [(String, StdioMCPTransport)] {
        guard let servers = config.mcpServers else { return [] }
        var result: [(String, StdioMCPTransport)] = []
        for (id, serverConfig) in servers where serverConfig.isEnabled {
            let transport = StdioMCPTransport(
                command: serverConfig.command,
                args: serverConfig.args ?? []
            )
            try? transport.start()
            result.append((id, transport))
        }
        return result
    }

    /// 从标准路径加载并自启动 transport：`~/.yunpat/mcp.json`
    public func loadDefault() -> [(String, StdioMCPTransport)] {
        let paths: [String] = [
            NSHomeDirectory() + "/.yunpat/mcp.json",
            NSHomeDirectory() + "/.config/yunpat/mcp.json"
        ]
        for path in paths {
            guard FileManager.default.fileExists(atPath: path),
                  let config = try? load(from: path)
            else { continue }
            return createTransports(from: config)
        }
        return []
    }
}
