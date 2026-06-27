import Foundation

public actor MCPClient {
    private var connections: [String: Process] = [:]
    public init() {}

    public func connect(serverID: String, command: String, args: [String] = []) async throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args
        process.standardInput = Pipe(); process.standardOutput = Pipe()
        try process.run(); connections[serverID] = process
        let request = MCPRequest(method: "initialize")
        try await send(to: serverID, data: try JSONEncoder().encode(request))
    }

    public func listTools(serverID: String) async throws -> [MCPToolDefinition] {
        let data = try JSONEncoder().encode(MCPRequest(method: "tools/list"))
        let responseData = try await sendAndReceive(serverID, data: data)
        return (try? JSONDecoder().decode([MCPToolDefinition].self, from: responseData)) ?? []
    }

    public func callTool(serverID: String, tool: String, arguments: [String: String]) async throws -> String {
        let request = MCPRequest(method: "tools/call", params: ["name": tool])
        let data = try JSONEncoder().encode(request)
        let responseData = try await sendAndReceive(serverID, data: data)
        return String(data: responseData, encoding: .utf8) ?? ""
    }

    public func disconnect(_ serverID: String) { connections[serverID]?.terminate(); connections[serverID] = nil }

    private func send(to serverID: String, data: Data) async throws {
        guard let stdin = (connections[serverID]?.standardInput as? Pipe) else { return }
        stdin.fileHandleForWriting.write(data); stdin.fileHandleForWriting.write("\n".data(using: .utf8)!)
    }

    private func sendAndReceive(_ serverID: String, data: Data) async throws -> Data {
        try await send(to: serverID, data: data)
        try await Task.sleep(nanoseconds: 500_000_000)
        guard let stdout = (connections[serverID]?.standardOutput as? Pipe) else { throw MCPError(message: "Not connected") }
        return stdout.fileHandleForReading.readDataToEndOfFile()
    }
}
