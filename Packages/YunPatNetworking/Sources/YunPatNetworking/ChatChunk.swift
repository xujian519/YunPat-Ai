import Foundation

public enum ChatChunk: Sendable {
    case text(String)
    case toolCall(id: String, name: String, arguments: String)
    case toolCallDelta(id: String, arguments: String)
    case finish(reason: FinishReason, usage: Usage?)
    case error(Error)
}

public enum FinishReason: String, Sendable {
    case stop
    case length
    case toolCalls = "tool_calls"
}
