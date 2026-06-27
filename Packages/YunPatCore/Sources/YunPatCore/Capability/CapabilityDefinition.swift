import Foundation

public enum CapabilitySource: String, Codable, Sendable { case builtin; case mcp; case plugin }
public enum CapabilityPermission: String, Codable, Sendable { case always; case perSession; case perCall; case never }
public enum CostLevel: String, Codable, Sendable { case free; case low; case medium; case high }

public struct CapabilityDefinition: Codable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let source: CapabilitySource
    public let permission: CapabilityPermission
    public let metadata: CapabilityMetadata
    public init(name: String, displayName: String, description: String, source: CapabilitySource = .builtin, permission: CapabilityPermission = .always, metadata: CapabilityMetadata = CapabilityMetadata()) {
        self.name = name; self.displayName = displayName; self.description = description; self.source = source; self.permission = permission; self.metadata = metadata
    }
}

public struct CapabilityMetadata: Codable, Sendable {
    public let costLevel: CostLevel
    public let requiresNetwork: Bool
    public let isIdempotent: Bool
    public let typicalUseCases: [String]
    public init(costLevel: CostLevel = .free, requiresNetwork: Bool = false, isIdempotent: Bool = true, typicalUseCases: [String] = []) {
        self.costLevel = costLevel; self.requiresNetwork = requiresNetwork; self.isIdempotent = isIdempotent; self.typicalUseCases = typicalUseCases
    }
}
