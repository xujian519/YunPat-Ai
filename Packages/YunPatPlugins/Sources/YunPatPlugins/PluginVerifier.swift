import Foundation
import Security

public actor PluginVerifier {
    public func verify(_ manifest: PluginManifest, bundle: Bundle) async throws -> Bool {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard compareVersions(appVersion, manifest.minAppVersion) >= 0 else { return false }
        guard let bundleURL = bundle.bundleURL as CFURL? else { return false }
        var staticCode: SecStaticCode? = nil
        guard SecStaticCodeCreateWithPath(bundleURL, [], &staticCode) == errSecSuccess, let code = staticCode else {
            return false
        }
        return SecStaticCodeCheckValidityWithErrors(code, [], nil, nil) == errSecSuccess
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let lhsParts: [Int] = lhs.components(separatedBy: ".").compactMap(Int.init)
        let rhsParts: [Int] = rhs.components(separatedBy: ".").compactMap(Int.init)
        for index in 0..<max(lhsParts.count, rhsParts.count) {
            let leftVal: Int = index < lhsParts.count ? lhsParts[index] : 0
            let rightVal: Int = index < rhsParts.count ? rhsParts[index] : 0
            if leftVal != rightVal { return leftVal - rightVal }
        }
        return 0
    }
}
