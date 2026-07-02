import Foundation

// MARK: - Declarative Plugin Secret Configuration

/// 声明式插件 secret 配置 — 对齐 Osaurus secrets schema
/// 插件声明需要的 API key 等凭证，Settings UI 自动生成配置表单
public struct PluginSecret: Codable, Sendable, Equatable {
    /// 唯一标识符（如 "api_key"）
    public let id: String
    /// 人类可读的标签（如 "OpenWeather API Key"）
    public let label: String
    /// 丰富的文字描述（支持 Markdown 链接）
    public let description: String?
    /// 是否为插件运行所必需
    public let required: Bool
    /// 获取此 secret 的外部 URL
    public let url: String?

    public init(
        id: String,
        label: String,
        description: String? = nil,
        required: Bool = true,
        url: String? = nil
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.required = required
        self.url = url
    }

    /// 生成 Settings UI 中显示的帮助文本
    public var helpText: String {
        var parts: [String] = []
        if let desc = description { parts.append(desc) }
        if let link = url { parts.append("[获取密钥](\(link))") }
        if required {
            parts.append("(必需)")
        } else {
            parts.append("(可选)")
        }
        return parts.joined(separator: " ")
    }
}
