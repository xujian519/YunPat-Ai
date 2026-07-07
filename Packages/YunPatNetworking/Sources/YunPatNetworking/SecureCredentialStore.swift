import Foundation
import LocalAuthentication
import Security

/// 凭证安全 — Keychain + 生物识别
///
/// 设计 §9：不落盘明文，Secure Enclave 密钥派生
public final class SecureCredentialStore: Sendable {
    public static let shared = SecureCredentialStore()

    private init() {}

    /// 存储 API Key 到 Keychain
    public func store(provider: String, apiKey: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "yunpat.\(provider)",
            kSecAttrService as String: "YunPat-Ai",
            kSecValueData as String: Data(apiKey.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
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
        guard
            let privateKey = SecKeyCreateRandomKey(
                [
                    kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                    kSecAttrKeySizeInBits as String: 256,
                    kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
                    kSecAttrApplicationTag as String: Data("com.yunpat.case.\(caseId)".utf8),
                    kSecPrivateKeyAttrs as String: [
                        kSecAttrIsPermanent as String: true
                    ]
                ] as CFDictionary, &error)
        else {
            throw CredentialError.keyGenFailed(error?.takeRetainedValue().localizedDescription)
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
            let pubData = SecKeyCopyExternalRepresentation(publicKey, &error) as? Data
        else {
            throw CredentialError.keyGenFailed(error?.takeRetainedValue().localizedDescription)
        }
        return pubData
    }

    /// 使用案件密钥加密数据
    public func encryptData(_ data: Data, for caseId: String) throws -> Data {
        var error: Unmanaged<CFError>?
        let tag = Data("com.yunpat.case.\(caseId)".utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecAttrApplicationTag as String: tag,
            kSecReturnRef as String: true
        ]
        var keyRef: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &keyRef) == errSecSuccess,
              let result = keyRef,
              let publicKey = SecKeyCopyPublicKey(unsafeDowncast(result, to: SecKey.self)) else {
            throw CredentialError.keyGenFailed("Case key not found for \(caseId)")
        }
        guard let encrypted = SecKeyCreateEncryptedData(
            publicKey,
            .eciesEncryptionCofactorX963SHA256AESGCM,
            data as CFData,
            &error
        ) as? Data else {
            throw CredentialError.keyGenFailed(error?.takeRetainedValue().localizedDescription)
        }
        return encrypted
    }
}
