import Foundation

// MARK: - HTTPMCPTransport

/// HTTP 传输 — POST JSON-RPC 请求，直接返回 JSON 响应
///
/// 适用于 MCP "Streamable HTTP" transport 的非流式模式（单一请求-响应）。
/// 服务端必须返回 `Content-Type: application/json` + JSON-RPC body。
public final class HTTPMCPTransport: MCPTransport, Sendable {

    private let url: URL
    private let headers: [String: String]
    private let session: URLSession

    public init(url: URL, headers: [String: String] = [:], session: URLSession = .shared) {
        self.url = url
        self.headers = headers
        self.session = session
    }

    public func send(_ payload: Data) async throws -> Data {
        var req: URLRequest = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        req.httpBody = payload

        let (data, response): (Data, URLResponse) = try await session.data(for: req)
        try Self.validate(response)
        return data
    }

    public func close() async throws {}

    public static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MCPError(message: "Non-HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw MCPError(message: "HTTP \(http.statusCode)")
        }
    }
}

// MARK: - SSEMCPTransport

/// SSE 传输 — MCP Streamable HTTP transport 的 SSE 模式
///
/// 客户端 POST JSON-RPC 请求，服务端通过 Server-Sent Events 流式推送 JSON-RPC 消息。
/// 此实现解析 SSE 事件流，返回与请求 id 匹配的 JSON-RPC 响应。
///
/// 如果服务端对 SSE 请求返回 `Content-Type: application/json`（降级为非流式），
/// 则直接收集完整 body 返回。
public final class SSEMCPTransport: MCPTransport, Sendable {

    private let url: URL
    private let headers: [String: String]
    private let session: URLSession

    public init(url: URL, headers: [String: String] = [:], session: URLSession = .shared) {
        self.url = url
        self.headers = headers
        self.session = session
    }

    public func send(_ payload: Data) async throws -> Data {
        var req: URLRequest = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        req.httpBody = payload

        let (bytes, response): (URLSession.AsyncBytes, URLResponse) = try await session.bytes(for: req)
        try HTTPMCPTransport.validate(response)

        let contentType: String = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""

        if contentType.contains("application/json") {
            var data: Data = Data()
            for try await byte in bytes { data.append(byte) }
            return data
        }

        let requestId: Int? = extractId(from: payload)

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr: String = String(line.dropFirst(6))
            guard let jsonData: Data = jsonStr.data(using: .utf8) else { continue }

            if let resp: [String: Any] = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let respId: Int? = resp["id"] as? Int
                if respId == requestId {
                    return jsonData
                }
            }
        }

        throw MCPError(message: "No matching response in SSE stream")
    }

    public func close() async throws {}

    private func extractId(from payload: Data) -> Int? {
        (try? JSONSerialization.jsonObject(with: payload) as? [String: Any])?["id"] as? Int
    }
}
