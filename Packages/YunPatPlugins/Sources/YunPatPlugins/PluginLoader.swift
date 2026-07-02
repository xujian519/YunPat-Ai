import Foundation

public actor PluginLoader {
    private var loadedBundles: [String: Bundle] = [:]

    public func loadManifest(from path: URL) async throws -> PluginManifest {
        guard let bundle = Bundle(url: path) else { throw PluginError.bundleNotFound }
        try bundle.loadAndReturnError()
        guard let manifestURL = bundle.url(forResource: "manifest", withExtension: "json"),
            let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data)
        else { throw PluginError.manifestNotFound }
        loadedBundles[manifest.id] = bundle
        return manifest
    }

    public func unload(_ pluginID: String) {
        loadedBundles[pluginID]?.unload()
        loadedBundles[pluginID] = nil
    }
}

public enum PluginError: Error {
    case bundleNotFound
    case manifestNotFound
    case verificationFailed
}
