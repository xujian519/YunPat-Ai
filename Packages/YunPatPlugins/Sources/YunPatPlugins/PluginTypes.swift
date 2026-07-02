import Foundation // swiftlint:disable:this file_name
import YunPatCore

public enum PluginLevel: String, Codable, Sendable {
    case tool
    case feature
    case mcpBridge
}

public struct PluginManifest: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let minAppVersion: String
    public let level: PluginLevel
    public let description: String
    public let author: String
    public let permissions: [PluginPermission]
    public init(
        id: String, name: String, version: String, minAppVersion: String = "1.0.0", level: PluginLevel = .tool,
        description: String = "", author: String = "", permissions: [PluginPermission] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.minAppVersion = minAppVersion
        self.level = level
        self.description = description
        self.author = author
        self.permissions = permissions
    }
}

public enum PluginPermission: String, Codable, Sendable {
    case fileRead
    case fileWrite
    case networkAPI
    case networkArbitrary
    case shell
    case accessibility
    case modelAccess
}
public enum PluginState: String, Sendable {
    case installed
    case verified
    case loaded
    case enabled
    case disabled
    case failed
    case uninstalled
}

public struct PluginEntry: Sendable {
    public let manifest: PluginManifest
    public var state: PluginState
    public init(manifest: PluginManifest, state: PluginState) {
        self.manifest = manifest
        self.state = state
    }
}

public protocol YunPatPlugin: Sendable {
    var manifest: PluginManifest { get }
    func activate() async throws
    func deactivate() async throws
    func verify() async throws -> Bool
    var capabilities: [CapabilityDefinition] { get }
}
