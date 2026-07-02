import Foundation

public struct Message: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
        case tool
    }
    public let role: Role
    public let content: String
    public let toolCallID: String?
    public let name: String?
    public init(role: Role, content: String, toolCallID: String? = nil, name: String? = nil) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.name = name
    }
}
