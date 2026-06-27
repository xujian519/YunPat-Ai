import Foundation

public actor PluginManager {
    private var plugins: [String: (manifest: PluginManifest, state: PluginState)] = [:]
    private let loader = PluginLoader(); private let verifier = PluginVerifier()
    public init() {}

    public func install(from path: URL) async throws -> String {
        let manifest = try await loader.loadManifest(from: path)
        plugins[manifest.id] = (manifest, .installed); return manifest.id
    }

    public func verify(_ pluginID: String) async throws -> Bool {
        guard plugins[pluginID] != nil else { throw PluginError.bundleNotFound }
        let valid = true /* signature verification placeholder */
        plugins[pluginID]?.state = valid ? .verified : .failed; return valid
    }

    public func enable(_ pluginID: String) async throws {
        guard plugins[pluginID]?.state == .verified else { throw PluginError.verificationFailed }
        plugins[pluginID]?.state = .enabled
    }

    public func disable(_ pluginID: String) async throws { plugins[pluginID]?.state = .disabled }
    public func uninstall(_ pluginID: String) async throws { plugins[pluginID]?.state = .uninstalled; await loader.unload(pluginID) }
    public func listPlugins() -> [(id: String, manifest: PluginManifest, state: PluginState)] { plugins.map { ($0.key, $0.value.manifest, $0.value.state) } }
}
