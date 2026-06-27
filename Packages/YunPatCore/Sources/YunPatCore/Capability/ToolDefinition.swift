import Foundation

public enum ToolSource: String, Codable, Sendable { case builtin; case mcp; case plugin }
public enum ToolPermission: String, Codable, Sendable { case always; case perSession; case perCall; case never }

public struct ToolDefinition: Codable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let parameters: String
    public let source: ToolSource
    public let permission: ToolPermission
    public init(name: String, displayName: String, description: String, parameters: String = "{}", source: ToolSource = .builtin, permission: ToolPermission = .always) {
        self.name = name; self.displayName = displayName; self.description = description; self.parameters = parameters; self.source = source; self.permission = permission
    }
}
