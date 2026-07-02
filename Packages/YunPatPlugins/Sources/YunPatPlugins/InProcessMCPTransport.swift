import Foundation

/// In-Process 传输 — 不启动子进程、不走网络，直接在内存中调用 MCPServer 处理请求
///
/// 用途：
/// 1. **嵌入式 MCP** — App 内直接注册 MCP 工具，无需外部进程
/// 2. **测试** — 完全离线的 MCP 往返测试（t0 可跑）
/// 3. **开发** — 快速验证 MCP 协议交互，无启动开销
///
/// 工作方式：将 JSON-RPC payload 直接传给 MCPServer.handleRequest()，返回响应 Data。
/// 序列化/反序列化仍走 JSON（保持协议一致性），但无进程/网络开销。
public final class InProcessMCPTransport: MCPTransport, @unchecked Sendable {

    private let server: MCPServer

    public init(server: MCPServer) {
        self.server = server
    }

    public func send(_ payload: Data) async throws -> Data {
        try await server.handleRequest(payload)
    }

    public func close() async throws {}
}
