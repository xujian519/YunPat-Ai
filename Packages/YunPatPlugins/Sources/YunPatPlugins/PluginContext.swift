import Foundation
import YunPatCore

// MARK: - PluginContext

/// 插件运行时上下文 — 对齐 Osaurus PluginContext 设计（Plugin.swift:952-993）
///
/// 每个插件实例持有自己的工具注册表，工具名自动以 `plugin_id:` 为前缀隔离。
/// 工具调用时自动注入 `_secrets` 和 `_context_folder` 字段。
public actor PluginContext {

    public let pluginID: String
    public let manifest: PluginManifest

    /// 插件提供的 secrets 键值对（由用户在 Settings UI 中填写）
    private var secrets: [String: String] = [:]

    /// 插件本地工具注册表，key = 工具全名（含前缀）
    private var tools: [String: ToolHandler] = [:]

    /// 工具描述（供 ToolDispatch.allToolSpecs 使用）
    private var specs: [String: ToolSpec] = [:]

    /// 插件 bundle 来源路径（用于签名验证）
    public let sourceURL: URL?

    public init(pluginID: String, manifest: PluginManifest, secrets: [String: String] = [:], sourceURL: URL? = nil) {
        self.pluginID = pluginID
        self.manifest = manifest
        self.secrets = secrets
        self.sourceURL = sourceURL
    }

    // MARK: - Secret Management

    /// 更新 secrets（由 Settings UI 调用）
    public func updateSecrets(_ newSecrets: [String: String]) {
        self.secrets = newSecrets
    }

    /// 获取某个 secret 的值
    public func secretValue(for key: String) -> String? {
        secrets[key]
    }

    // MARK: - Tool Registration

    /// 注册一个工具，名称自动添加 `plugin_id:` 前缀
    public func register(name: String, description: String, handler: @escaping ToolHandler) {
        let qualified: String = "\(pluginID):\(name)"
        let capturedSecrets: [String: String] = secrets
        let injectingHandler: ToolHandler = { _, rawInput, ctx in
            var augmented: [String: Any] = rawInput
            if !capturedSecrets.isEmpty {
                augmented["_secrets"] = capturedSecrets
            }
            augmented["_context_folder"] = ctx.projectFolder
            return await handler(qualified, augmented, ctx)
        }
        tools[qualified] = injectingHandler
        specs[qualified] = ToolSpec(name: qualified, description: description)
    }

    /// 注册一个 TypedTool
    public func register<T: TypedTool>(tool: T) where T.Args: Decodable & Sendable {
        register(name: tool.name, description: tool.description, handler: tool.handler)
    }

    // MARK: - Tool Lookup

    /// 查找工具处理函数
    public func handler(for qualifiedName: String) -> ToolHandler? {
        tools[qualifiedName]
    }

    /// 所有已注册工具的描述
    public var allSpecs: [ToolSpec] {
        Array(specs.values)
    }

    // MARK: - Sync to ToolDispatch

    /// 将所有工具注册到全局 ToolDispatch，以 `plugin_id:` 前缀隔离
    public func syncToGlobal() {
        let dispatch: ToolDispatch = ToolDispatch.shared
        for (name, handler) in tools {
            dispatch.register(name: name, description: specs[name]?.description ?? "", handler: handler)
        }
    }

    /// 从全局 ToolDispatch 注销所有本插件工具
    public func unsyncFromGlobal() {
        let dispatch: ToolDispatch = ToolDispatch.shared
        for name in tools.keys {
            dispatch.unregister(name: name)
        }
    }

    // MARK: - Helpers

    /// 检查插件所需的 must 级别 secret 是否都已配置
    public var hasRequiredSecrets: Bool {
        for secret in manifest.secrets ?? [] where secret.required {
            guard secrets[secret.id] != nil, !(secrets[secret.id]?.isEmpty ?? true) else {
                return false
            }
        }
        return true
    }
}
