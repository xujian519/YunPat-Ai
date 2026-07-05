import Foundation

/// Anthropic Claude API provider。
///
/// Anthropic 的 API 与 OpenAI 不兼容：
/// - `system` 在请求顶层，不在 messages 数组中
/// - SSE 事件用 `event:` 字段区分类型（message_start / content_block_delta / message_delta / message_stop）
/// - 需要 `anthropic-version` header
public final class AnthropicProvider: ModelBackend {
    public let provider: ModelProvider = ModelProvider.anthropic
    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    private static let apiVersion: String = "2023-06-01"

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1") ?? URL(fileURLWithPath: "/invalid"),
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    public var rateLimit: RateLimitInfo? { get async { nil } }

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                guard !apiKey.isEmpty else {
                    continuation.finish(throwing: RateLimitError(message: "API key is empty"))
                    return
                }

                do {
                    let urlRequest = try buildRequest(request)
                    let (bytes, response): (URLSession.AsyncBytes, URLResponse) = try await session.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: ProviderError.invalidResponse)
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        let body: String = try await collectErrorBody(bytes)
                        if httpResponse.statusCode == 429 {
                            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                                .flatMap(Double.init)
                            continuation.finish(
                                throwing: RateLimitError(
                                    retryAfter: retryAfter,
                                    message: "Rate limited: \(body)"
                                ))
                        } else {
                            continuation.finish(throwing: ProviderError.httpError(httpResponse.statusCode, body))
                        }
                        return
                    }

                    // Anthropic SSE 解析：`event: type\ndata: {...}\n\n`
                    var currentEventType: String = ""
                    for try await line in bytes.lines {
                        if line.hasPrefix("event: ") {
                            currentEventType = String(line.dropFirst(7))
                        } else if line.hasPrefix("data: ") {
                            let payload = String(line.dropFirst(6))
                            guard let data = payload.data(using: .utf8),
                                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                            else { continue }
                            parseAnthropicSSE(eventType: currentEventType, json: json, into: continuation)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func listModels() async throws -> [ModelInfo] { [] }

    public func capabilities() -> ModelCapabilities {
        ModelCapabilities(
            supportsStreaming: true,
            supportsToolCalling: true,
            maxContextTokens: 200_000,
            supportsVision: true
        )
    }

    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy {
        .retry(after: error.retryAfter ?? 5.0)
    }

    // MARK: - Private

    private func buildRequest(_ request: ChatRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        // Anthropic: system 在顶层，不在 messages 数组
        var body: [String: Any] = [
            "model": request.model,
            "messages": request.messages.map { msg -> [String: Any] in
                ["role": msg.role.rawValue, "content": msg.content]
            },
            "stream": true,
            "max_tokens": request.maxTokens ?? 4096
        ]
        if let systemPrompt = request.systemPrompt {
            body["system"] = systemPrompt
        }
        if let temp = request.temperature { body["temperature"] = temp }
        if let tools = request.tools, !tools.isEmpty {
            body["tools"] = tools.map { tool in
                var schema: Any = ["type": "object", "properties": [:]]
                if let data = tool.parameters.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) {
                    schema = parsed
                }
                return [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": schema
                ] as [String: Any]
            }
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private func parseAnthropicSSE(
        eventType: String,
        json: [String: Any],
        into continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation
    ) {
        switch eventType {
        case "content_block_delta":
            // { "type": "content_block_delta", "delta": { "type": "text_delta", "text": "..." } }
            if let delta = json["delta"] as? [String: Any],
                let text = delta["text"] as? String {
                continuation.yield(.text(text))
            }

        case "message_delta":
            // { "type": "message_delta", "delta": { "stop_reason": "end_turn" }, "usage": { "output_tokens": 42 } }
            if let delta = json["delta"] as? [String: Any],
                let stopReason = delta["stop_reason"] as? String {
                let reason: FinishReason =
                    switch stopReason {
                    case "end_turn", "stop_sequence": .stop
                    case "max_tokens": .length
                    case "tool_use": .toolCalls
                    default: .stop
                    }
                var usage: Usage?
                if let usageDict = json["usage"] as? [String: Any] {
                    usage = Usage(
                        promptTokens: usageDict["input_tokens"] as? Int ?? 0,
                        completionTokens: usageDict["output_tokens"] as? Int ?? 0,
                        totalTokens: (usageDict["input_tokens"] as? Int ?? 0)
                            + (usageDict["output_tokens"] as? Int ?? 0)
                    )
                }
                continuation.yield(.finish(reason: reason, usage: usage))
            }

        case "message_stop":
            // 流结束
            break

        default:
            break
        }
    }

    private func collectErrorBody(_ bytes: URLSession.AsyncBytes) async throws -> String {
        var body: String = ""
        for try await line in bytes.lines { body += line }
        return body
    }
}
