import Foundation
import Security

public actor PluginVerifier {
    public func verify(_ manifest: PluginManifest, bundle: Bundle) async throws -> Bool {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard compareVersions(appVersion, manifest.minAppVersion) >= 0 else { return false }
        guard let bundleURL = bundle.bundleURL as CFURL? else { return false }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL, [], &staticCode) == errSecSuccess, let code = staticCode else { return false }
        return SecStaticCodeCheckValidityWithErrors(code, [], nil, nil) == errSecSuccess
    }

    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let p1 = v1.components(separatedBy: ".").compactMap(Int.init); let p2 = v2.components(separatedBy: ".").compactMap(Int.init)
        for i in 0..<max(p1.count, p2.count) { let a = i < p1.count ? p1[i] : 0; let b = i < p2.count ? p2[i] : 0; if a != b { return a - b } }
        return 0
    }
}
