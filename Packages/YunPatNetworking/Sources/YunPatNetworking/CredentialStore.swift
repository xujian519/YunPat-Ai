import Foundation
import Security

public struct CredentialStore: Sendable {
    public static let shared = CredentialStore()

    public func store(provider: ModelProvider, apiKey: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "yunpat.\(provider.rawValue)",
            kSecAttrService as String: "YunPat-Ai",
            kSecValueData as String: apiKey.data(using: .utf8)!,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.keychainError(status)
        }
    }

    public func apiKey(for provider: ModelProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "yunpat.\(provider.rawValue)",
            kSecAttrService as String: "YunPat-Ai",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(for provider: ModelProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "yunpat.\(provider.rawValue)",
            kSecAttrService as String: "YunPat-Ai",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum CredentialError: Error {
    case keychainError(OSStatus)
}
