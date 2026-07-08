import Foundation

/// Session 冻结的能力清单 — 注入系统 prompt 静态前缀（KV-stable）
/// 模型不可感知此 list 之外的 capability，直到 session 结束。
public struct CapabilityManifest: Sendable {
    public let entries: [ManifestEntry]
    /// 渲染文本块（byte-stable，跨迭代不变）
    public let renderedBlock: String

    public init(entries: [ManifestEntry]) {
        self.entries = entries
        self.renderedBlock = Self.render(entries)
    }

    /// 从 CapabilityRegistry 和 SkillManager 生成 manifest（含工具树）
    public static func build(
        registry: CapabilityRegistry,
        skills: [SkillContent]
    ) async -> CapabilityManifest {
        var entries: [ManifestEntry] = []

        for cap in await registry.listCapabilities() {
            // 收集该 capability 下的工具
            let tools: [String] = cap.toolNames
            entries.append(
                ManifestEntry(
                    name: cap.name,
                    displayName: cap.displayName,
                    description: cap.description,
                    kind: .tool,
                    costLevel: cap.metadata.costLevel,
                    requiresNetwork: cap.metadata.requiresNetwork,
                    subItems: tools
                ))
        }

        for skill in skills {
            entries.append(
                ManifestEntry(
                    name: skill.manifest.name,
                    displayName: skill.manifest.displayName,
                    description: skill.manifest.description,
                    kind: .skill,
                    costLevel: .low,
                    requiresNetwork: false,
                    subItems: []
                ))
        }

        return CapabilityManifest(entries: entries)
    }

    /// 渲染稳定文本块（能力→工具二级结构）
    private static func render(_ entries: [ManifestEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        var lines: [String] = ["【可用能力】"]
        lines.append("先浏览能力列表，然后选择对应工具。使用 capabilities_discover 搜索具体能力。")
        lines.append("")

        for error in entries {
            let cost = error.costLevel.rawValue
            let net = error.requiresNetwork ? "🌐" : ""
            let kindIcon = error.kind == .skill ? "📚" : "🔧"
            lines.append("## \(kindIcon) \(error.displayName)")
            lines.append("- ID: `\(error.name)` | 成本: \(cost)\(net)")
            lines.append("- 描述: \(error.description)")

            if !error.subItems.isEmpty {
                lines.append("- 可用工具: \(error.subItems.map { "`\($0)`" }.joined(separator: ", "))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

/// Manifest 条目 — 对应一个能力或技能
public struct ManifestEntry: Sendable, Equatable {
    public let name: String
    public let displayName: String
    public let description: String
    public let kind: CapabilityKind
    public let costLevel: CostLevel
    public let requiresNetwork: Bool
    public let subItems: [String]
    public init(
        name: String, displayName: String, description: String, kind: CapabilityKind, costLevel: CostLevel,
        requiresNetwork: Bool, subItems: [String] = []
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.kind = kind
        self.costLevel = costLevel
        self.requiresNetwork = requiresNetwork
        self.subItems = subItems
    }
}

/// 能力类型 — 工具或技能
public enum CapabilityKind: String, Sendable {
    case tool
    case skill
    case method
}
