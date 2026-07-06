import Foundation
import Security

public struct CredentialStore: Sendable {
    public static let shared = CredentialStore()

    public func store(provider: ModelProvider, apiKey: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "yunpat.\(provider.rawValue)",
            kSecAttrService as String: "YunPat-Ai",
            kSecValueData as String: Data(apiKey.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
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
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
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
        case .keychainError(let status): "Keychain 错误 (OSStatus: \(status))"
        case .storeFailed(let status): "Keychain 存储失败 (OSStatus: \(status))"
        case .biometricsUnavailable(let message): message ?? "生物识别不可用"
        case .keyGenFailed(let message): message ?? "密钥生成失败"
        case .decryptFailed: "解密失败"
        }
    }
}
