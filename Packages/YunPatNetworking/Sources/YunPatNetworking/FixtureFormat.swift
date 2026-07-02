import Foundation

// MARK: - Fixture Document (Codable JSON 格式)

/// Fixture 格式命名空间
public enum FixtureFormat {}

/// Fixture 文档根结构 — 一次录制会话的完整快照
///
/// JSON 示例:
/// ```json
/// { "version": 1, "provider": "deepseek", "records": [ { ... }, { ... } ] }
/// ```
public struct FixtureDocument: Codable, Sendable {
    public let version: Int
    public let provider: String
    public var records: [FixtureRecord]

    public init(version: Int = 1, provider: String, records: [FixtureRecord]) {
        self.version = version
        self.provider = provider
        self.records = records
    }
}

/// 单次 chat() 调用的录制记录（请求摘要 + 响应 chunk 序列）
public struct FixtureRecord: Codable, Sendable {
    /// 请求的 model 名（用于调试/匹配）
    public let requestModel: String
    /// 请求消息数（用于调试）
    public let requestMessageCount: Int
    /// 响应的 chunk 序列（按真实 API 顺序）
    public var chunks: [FixtureChunk]

    public init(requestModel: String, requestMessageCount: Int, chunks: [FixtureChunk]) {
        self.requestModel = requestModel
        self.requestMessageCount = requestMessageCount
        self.chunks = chunks
    }
}

/// ChatChunk 的 Codable 中间表示
///
/// 所有字段可选，用 `kind` 区分枚举 case。
public struct FixtureChunk: Codable, Sendable {

    public let kind: String
    public let text: String?
    public let toolCallId: String?
    public let toolCallName: String?
    public let toolCallArguments: String?
    public let finishReason: String?
    public let usage: FixtureUsage?
    public let errorMessage: String?

    private init(
        kind: String, text: String? = nil, toolCallId: String? = nil,
        toolCallName: String? = nil, toolCallArguments: String? = nil,
        finishReason: String? = nil, usage: FixtureUsage? = nil,
        errorMessage: String? = nil
    ) {
        self.kind = kind
        self.text = text
        self.toolCallId = toolCallId
        self.toolCallName = toolCallName
        self.toolCallArguments = toolCallArguments
        self.finishReason = finishReason
        self.usage = usage
        self.errorMessage = errorMessage
    }

    public static func text(_ string: String) -> FixtureChunk {
        FixtureChunk(kind: "text", text: string)
    }
    public static func toolCall(id: String, name: String, arguments: String) -> FixtureChunk {
        FixtureChunk(kind: "toolCall", toolCallId: id, toolCallName: name, toolCallArguments: arguments)
    }
    public static func toolCallDelta(id: String, arguments: String) -> FixtureChunk {
        FixtureChunk(kind: "toolCallDelta", toolCallId: id, toolCallArguments: arguments)
    }
    public static func finish(reason: FinishReason, usage: Usage?) -> FixtureChunk {
        FixtureChunk(kind: "finish", finishReason: reason.rawValue, usage: usage.map(FixtureUsage.init))
    }
    public static func error(_ message: String) -> FixtureChunk {
        FixtureChunk(kind: "error", errorMessage: message)
    }
}

public struct FixtureUsage: Codable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }

    public init(_ usage: Usage) {
        self.promptTokens = usage.promptTokens
        self.completionTokens = usage.completionTokens
        self.totalTokens = usage.totalTokens
    }
}

// MARK: - ChatChunk <-> FixtureChunk 双向转换

extension FixtureChunk {

    /// 从 ChatChunk 构造（录制用）
    public init(from chunk: ChatChunk) {
        switch chunk {
        case .text(let string):
            self = .text(string)
        case .toolCall(let id, let name, let arguments):
            self = .toolCall(id: id, name: name, arguments: arguments)
        case .toolCallDelta(let id, let arguments):
            self = .toolCallDelta(id: id, arguments: arguments)
        case .finish(let reason, let usage):
            self = .finish(reason: reason, usage: usage)
        case .error(let err):
            self = .error((err as? LocalizedError)?.errorDescription ?? err.localizedDescription)
        }
    }

    /// 转回 ChatChunk（回放用）
    public func toChatChunk() -> ChatChunk {
        switch kind {
        case "text":
            return .text(text ?? "")
        case "toolCall":
            return .toolCall(id: toolCallId ?? "", name: toolCallName ?? "", arguments: toolCallArguments ?? "")
        case "toolCallDelta":
            return .toolCallDelta(id: toolCallId ?? "", arguments: toolCallArguments ?? "")
        case "finish":
            let reason: FinishReason = FinishReason(rawValue: finishReason ?? "stop") ?? .stop
            let mappedUsage: Usage? = usage.map {
                Usage(promptTokens: $0.promptTokens, completionTokens: $0.completionTokens, totalTokens: $0.totalTokens)
            }
            return .finish(reason: reason, usage: mappedUsage)
        case "error":
            return .error(FixtureReplayError(message: errorMessage ?? "unknown fixture error"))
        default:
            return .text(text ?? "")
        }
    }
}

// MARK: - Errors

/// 回放期间的错误
public struct FixtureReplayError: Error, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
}

/// Replay fixture 耗尽（调用次数超过录制次数）
public struct FixtureExhaustedError: Error, Sendable {
    public let requestsMade: Int
    public let requestsRecorded: Int
    public init(requestsMade: Int, requestsRecorded: Int) {
        self.requestsMade = requestsMade
        self.requestsRecorded = requestsRecorded
    }
}
