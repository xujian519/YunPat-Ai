import Foundation

/// 工具注册表条目类型 — 对应 tools 数组中的每个元素
public struct ToolRecord: Codable, Sendable, Equatable {
    public let name: String
    public let source: String
    public let version: String
    /// 工具用途摘要（来自 frontmatter description）
    public let description: String?
    /// 触发场景列表（来自 When to Use）
    public let triggers: [String]?
    /// 典型工作流步骤（来自 Typical Workflow）
    public let workflow: [String]?

    public init(
        name: String, source: String = "builtin", version: String = "1.0.0",
        description: String? = nil, triggers: [String]? = nil,
        workflow: [String]? = nil
    ) {
        self.name = name
        self.source = source
        self.version = version
        self.description = description
        self.triggers = triggers
        self.workflow = workflow
    }
}

/// 工具注册表 — 对应 plugins/registry.json
public struct ToolManifest: Codable, Sendable {
    public let generated: String
    public let toolCount: Int
    public let tools: [ToolRecord]
}
