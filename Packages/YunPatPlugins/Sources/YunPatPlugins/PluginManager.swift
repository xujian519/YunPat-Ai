import Foundation

public actor PluginManager {
    private var plugins: [String: PluginEntry] = [:]
    private let loader = PluginLoader()
    private let verifier = PluginVerifier()
    public init() {}

    public func install(from path: URL) async throws -> String {
        let manifest = try await loader.loadManifest(from: path)
        plugins[manifest.id] = PluginEntry(manifest: manifest, state: .installed)
        return manifest.id
    }

    public func verify(_ pluginID: String) async throws -> Bool {
        guard let entry = plugins[pluginID] else { throw PluginError.bundleNotFound }
        guard let bundle = await loader.bundle(for: pluginID) else {
            plugins[pluginID]?.state = .failed
            return false
        }
        let valid: Bool = try await verifier.verify(entry.manifest, bundle: bundle)
        plugins[pluginID]?.state = valid ? .verified : .failed
        return valid
    }

    public func enable(_ pluginID: String) async throws {
        guard plugins[pluginID]?.state == .verified else { throw PluginError.verificationFailed }
        plugins[pluginID]?.state = .enabled
    }

    public func disable(_ pluginID: String) async throws { plugins[pluginID]?.state = .disabled }
    public func uninstall(_ pluginID: String) async throws {
        plugins[pluginID]?.state = .uninstalled
        await loader.unload(pluginID)
    }
    public func listPlugins() -> [PluginEntry] {
        Array(plugins.values)
    }
}
