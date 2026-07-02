import Foundation

/// 能力来源类型
public enum CapabilitySource: String, Codable, Sendable {
    case builtin
    case mcp
    case plugin
}
/// 能力权限级别
public enum CapabilityPermission: String, Codable, Sendable {
    case always
    case perSession
    case perCall
    case never
}
/// 能力成本级别
public enum CostLevel: String, Codable, Sendable {
    case free
    case low
    case medium
    case high
}

/// 能力定义 — 描述一个可注册的能力及其属性
public struct CapabilityDefinition: Codable, Sendable {
    public let name: String
    public let displayName: String
    public let description: String
    public let source: CapabilitySource
    public let permission: CapabilityPermission
    public let metadata: CapabilityMetadata
    public let toolNames: [String]
    public init(
        name: String, displayName: String, description: String, source: CapabilitySource = .builtin,
        permission: CapabilityPermission = .always, metadata: CapabilityMetadata = CapabilityMetadata(),
        toolNames: [String] = []
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.source = source
        self.permission = permission
        self.metadata = metadata
        self.toolNames = toolNames
    }
}

/// 能力元数据 — 成本、网络需求、幂等性、典型用例、依赖层级
public struct CapabilityMetadata: Codable, Sendable {
    public let costLevel: CostLevel
    public let requiresNetwork: Bool
    public let isIdempotent: Bool
    public let typicalUseCases: [String]
    /// T0 纯本地 / T1 软依赖(本地DB/索引) / T2 硬依赖(网络API/LLM)
    public let dependencyTier: ToolDependencyTier
    public init(
        costLevel: CostLevel = .free, requiresNetwork: Bool = false, isIdempotent: Bool = true,
        typicalUseCases: [String] = [], dependencyTier: ToolDependencyTier = .tier0
    ) {
        self.costLevel = costLevel
        self.requiresNetwork = requiresNetwork
        self.isIdempotent = isIdempotent
        self.typicalUseCases = typicalUseCases
        self.dependencyTier = dependencyTier
    }
}
