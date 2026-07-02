import Foundation

/// 网络安全策略 — 基础证书绑定与域名白名单
public struct NetworkPolicy: Sendable {
    /// 允许连接的域名（白名单模式）
    public let allowedDomains: Set<String>
    /// 是否启用证书绑定
    public let certificatePinningEnabled: Bool
    /// 绑定的证书 SHA256 指纹
    public let pinnedHashes: [String: String]

    public static let `default` = NetworkPolicy()

    public init(
        allowedDomains: Set<String> = [
            "api.openai.com",
            "api.anthropic.com",
            "api.deepseek.com",
            "open.bigmodel.cn"
        ],
        certificatePinningEnabled: Bool = false,
        pinnedHashes: [String: String] = [:]
    ) {
        self.allowedDomains = allowedDomains
        self.certificatePinningEnabled = certificatePinningEnabled
        self.pinnedHashes = pinnedHashes
    }

    /// 检查域名是否在白名单中
    public func isAllowed(host: String) -> Bool {
        allowedDomains.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    /// 验证证书 SHA256 是否匹配（基础检查）
    public func validateCertificate(host: String, sha256: String) -> Bool {
        guard certificatePinningEnabled, let expected = pinnedHashes[host] else { return true }
        return expected == sha256
    }

    /// 设置证书绑定（返回新实例）
    public func withPinning(domain: String, sha256: String) -> NetworkPolicy {
        var hashes: [String: String] = pinnedHashes
        hashes[domain] = sha256
        return NetworkPolicy(
            allowedDomains: allowedDomains,
            certificatePinningEnabled: true,
            pinnedHashes: hashes
        )
    }
}
