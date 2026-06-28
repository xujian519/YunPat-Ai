import Foundation
import Security
import LocalAuthentication

/// 凭证安全 — Keychain + 生物识别
///
/// 设计 §9：不落盘明文，Secure Enclave 密钥派生
public final class SecureCredentialStore: @unchecked Sendable {
    public static let shared = SecureCredentialStore()

    private init() {}

    /// 存储 API Key 到 Keychain
    public func store(provider: String, apiKey: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "yunpat.\(provider)",
            kSecAttrService as String: "com.yunpat.ai",
            kSecValueData as String: apiKey.data(using: .utf8)!,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.storeFailed(status)
        }
    }

    /// 从 Keychain 读取 API Key
    public func apiKey(for provider: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "yunpat.\(provider)",
            kSecAttrService as String: "com.yunpat.ai",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 生物识别验证（Touch ID / Face ID）
    public func authenticateWithBiometrics(reason: String = "验证身份以访问加密数据") async throws -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw CredentialError.biometricsUnavailable(error?.localizedDescription)
        }
        return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
    }

    /// 生成案件加密密钥（来自 Secure Enclave）
    public func generateCaseKey(caseId: String) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey([
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecAttrApplicationTag as String: "com.yunpat.case.\(caseId)".data(using: .utf8)!,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
            ]
        ] as CFDictionary, &error) else {
            throw CredentialError.keyGenFailed(error?.takeRetainedValue().localizedDescription)
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let pubData = SecKeyCopyExternalRepresentation(publicKey, &error) as? Data else {
            throw CredentialError.keyGenFailed(error?.takeRetainedValue().localizedDescription)
        }
        return pubData
    }

    /// 使用案件密钥加密数据
    public func encryptData(_ data: Data, for caseId: String) throws -> Data {
        // Placeholder — full implementation requires SecKeyCreateEncryptedData
        return data
    }
}
