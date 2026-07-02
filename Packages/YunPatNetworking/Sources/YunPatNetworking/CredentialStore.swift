import Foundation
import Security

public struct CredentialStore: Sendable {
    public static let shared = CredentialStore()

    public func store(provider: ModelProvider, apiKey: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "yunpat.\(provider.rawValue)",
            kSecAttrService as String: "YunPat-Ai",
            kSecValueData as String: apiKey.data(using: .utf8)!
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
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(for provider: ModelProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "yunpat.\(provider.rawValue)",
            kSecAttrService as String: "YunPat-Ai"
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum CredentialError: Error, LocalizedError {
    case keychainError(OSStatus)
    case storeFailed(OSStatus)
    case biometricsUnavailable(String?)
    case keyGenFailed(String?)
    case decryptFailed

    public var errorDescription: String? {
        switch self {
        case .keychainError(let s): "Keychain 错误 (OSStatus: \(s))"
        case .storeFailed(let s): "Keychain 存储失败 (OSStatus: \(s))"
        case .biometricsUnavailable(let m): m ?? "生物识别不可用"
        case .keyGenFailed(let m): m ?? "密钥生成失败"
        case .decryptFailed: "解密失败"
        }
    }
}
