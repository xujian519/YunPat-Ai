import Foundation

/// OpenAI API provider — 支持 OpenAI 和所有 OpenAI 兼容端点（DeepSeek、GLM 等）。
///
/// 通过 `baseURL` 参数切换端点：
/// - OpenAI: `https://api.openai.com/v1`
/// - DeepSeek: `https://api.deepseek.com/v1`
/// - GLM: `https://open.bigmodel.cn/api/paas/v4`
public final class OpenAIProvider: ModelBackend {
    public let provider: ModelProvider
    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    // swiftlint:disable:next force_unwrapping
    public static let defaultBaseURL: URL = URL(string: "https://api.openai.com/v1")!

    public init(
        apiKey: String,
        baseURL: URL = OpenAIProvider.defaultBaseURL,
        provider: ModelProvider = .openai,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.provider = provider
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
                    let urlRequest: URLRequest = try buildRequest(request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)

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

                    // SSE 流式解析：`data: {...}\n\n`
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" {
                            continuation.yield(.finish(reason: .stop, usage: nil))
                            break
                        }

                        guard let data = payload.data(using: .utf8),
                            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        parseSSEChunk(json, into: continuation)
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
            maxContextTokens: 128_000,
            supportsVision: provider == .openai
        )
    }

    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy {
        .retry(after: error.retryAfter ?? 5.0)
    }

    // MARK: - Private

    private func buildRequest(_ request: ChatRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        var body: [String: Any] = [
            "model": request.model,
            "messages": request.messages.map { msg -> [String: Any] in
                var dict: [String: Any] = ["role": msg.role.rawValue, "content": msg.content]
                if let id = msg.toolCallID { dict["tool_call_id"] = id }
                if let name = msg.name { dict["name"] = name }
                return dict
            },
            "stream": true
        ]
        if let systemPrompt = request.systemPrompt {
            // system 作为第一条 message
            body["messages"] =
                [
                    ["role": "system", "content": systemPrompt]
                ] + (body["messages"] as? [[String: Any]] ?? [])
        }
        if let temp = request.temperature { body["temperature"] = temp }
        if let maxTokens = request.maxTokens { body["max_tokens"] = maxTokens }
        if let tools = request.tools, !tools.isEmpty {
            body["tools"] = tools.map { tool in
                var params: Any = [:]
                if let data = tool.parameters.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) {
                    params = parsed
                }
                return [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": params
                    ]
                ] as [String: Any]
            }
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private func parseSSEChunk(
        _ json: [String: Any], into continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation
    ) {
        // choices[0].delta.content
        if let choices = json["choices"] as? [[String: Any]],
            let firstChoice = choices.first {
            let delta: [String: Any]? = firstChoice["delta"] as? [String: Any]

            if let content = delta?["content"] as? String, !content.isEmpty {
                continuation.yield(.text(content))
            }
            if let toolCalls = delta?["tool_calls"] as? [[String: Any]] {
                for toolCall in toolCalls {
                    if let id = toolCall["id"] as? String,
                        let function = toolCall["function"] as? [String: Any],
                        let name = function["name"] as? String {
                        continuation.yield(
                            .toolCall(id: id, name: name, arguments: (function["arguments"] as? String) ?? ""))
                    } else if let function = toolCall["function"] as? [String: Any],
                        let args = function["arguments"] as? String {
                        let id: String = (toolCall["id"] as? String) ?? ""
                        continuation.yield(.toolCallDelta(id: id, arguments: args))
                    }
                }
            }

            // finish_reason
            if let finishReason = firstChoice["finish_reason"] as? String {
                let reason: FinishReason =
                    switch finishReason {
                    case "stop": .stop
                    case "length": .length
                    case "tool_calls": .toolCalls
                    default: .stop
                    }
                // usage（如果存在）
                var usage: Usage?
                if let usageDict = json["usage"] as? [String: Any] {
                    usage = Usage(
                        promptTokens: usageDict["prompt_tokens"] as? Int ?? 0,
                        completionTokens: usageDict["completion_tokens"] as? Int ?? 0,
                        totalTokens: usageDict["total_tokens"] as? Int ?? 0
                    )
                }
                continuation.yield(.finish(reason: reason, usage: usage))
            }
        }
    }

    private func collectErrorBody(_ bytes: URLSession.AsyncBytes) async throws -> String {
        var body: String = ""
        for try await line in bytes.lines { body += line }
        return body
    }
}

public enum ProviderError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid HTTP response"
        case .httpError(let code, let body): "HTTP \(code): \(body)"
        }
    }
}
