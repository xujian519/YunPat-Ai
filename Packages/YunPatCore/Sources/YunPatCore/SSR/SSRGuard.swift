import Foundation

// MARK: - SSR (Server-Side Request Forgery) Guard

/// SSR（服务端请求伪造）防护 — 防止工具被诱导向内网/本地/云元数据端点发送请求
public enum SSRGuard: Sendable {

    // MARK: - Check Result

    public struct CheckResult: Sendable, Equatable {
        public let ok: Bool
        public let errorCode: ToolErrorCode?
        public let message: String?
        public init(ok: Bool, errorCode: ToolErrorCode? = nil, message: String? = nil) {
            self.ok = ok
            self.errorCode = errorCode
            self.message = message
        }
    }

    // MARK: - Public API

    /// 检查 URL 是否应被 SSR 策略阻止
    /// - Parameters:
    ///   - urlString: 待检查的 URL
    ///   - allowPrivate: 为 true 时完全跳过内网检查
    public static func checkSSRF(_ urlString: String, allowPrivate: Bool) -> CheckResult {
        guard let url = URL(string: urlString) else {
            return CheckResult(ok: false, errorCode: .invalidArgs, message: "Malformed URL")
        }

        // 阻止非 HTTP(S) 方案
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return CheckResult(
                ok: false, errorCode: .ssrfBlocked,
                message: "Only http/https schemes allowed; got \(url.scheme ?? "none")"
            )
        }

        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return CheckResult(ok: false, errorCode: .invalidArgs, message: "No host in URL")
        }

        // 云元数据端点始终拦截，即使 allowPrivate=true
        if isBlockedHostname(host) {
            return CheckResult(
                ok: false, errorCode: .ssrfBlocked,
                message: "Blocked hostname: \(host)"
            )
        }

        // 允许内网绕行（但不绕行云元数据）
        if allowPrivate { return CheckResult(ok: true) }

        // IP 检查
        if isPrivateIPv4(host) {
            return CheckResult(
                ok: false, errorCode: .ssrfBlocked,
                message: "Private IPv4 address blocked: \(host)"
            )
        }
        if isReservedIPv6(host) {
            return CheckResult(
                ok: false, errorCode: .ssrfBlocked,
                message: "Reserved IPv6 address blocked: \(host)"
            )
        }

        return CheckResult(ok: true)
    }

    // MARK: - IPv4 Detection

    /// 检查是否为私有/保留 IPv4 地址
    /// 涵盖: loopback, RFC1918, link-local, CGNAT, broadcast, reserved
    public static func isPrivateIPv4(_ addr: String) -> Bool {
        guard let octets = parseIPv4(addr) else { return false }
        switch (octets.oct0, octets.oct1, octets.oct2, octets.oct3) {
        case (10, _, _, _): return true  // RFC1918 Class A
        case (172, 16...31, _, _): return true  // RFC1918 Class B
        case (192, 168, _, _): return true  // RFC1918 Class C
        case (127, _, _, _): return true  // Loopback
        case (169, 254, _, _): return true  // Link-local
        case (100, 64...127, _, _): return true  // CGNAT (RFC 6598)
        case (0, _, _, _): return true  // "This" network
        case (240..., _, _, _): return true  // Reserved / Class E
        case (255, 255, 255, 255): return true  // Broadcast
        default: return false
        }
    }

    // MARK: - IPv6 Detection

    /// 检查是否为保留 IPv6 地址
    public static func isReservedIPv6(_ addr: String) -> Bool {
        let lower = addr.lowercased()
        if lower == "::1" { return true }
        if lower.hasPrefix("fe80:") { return true }  // Link-local
        if lower.hasPrefix("fc") || lower.hasPrefix("fd") { return true }  // Unique Local
        if lower.hasPrefix("ff") { return true }  // Multicast
        if lower.hasPrefix("::ffff:") { return true }  // IPv4-mapped (always maps to IPv4)
        return false
    }

    // MARK: - Hostname Blocklist

    /// 检查主机名是否在阻止名单中
    public static func isBlockedHostname(_ host: String) -> Bool {
        let lower = host.lowercased()
        let blocked: Set<String> = [
            "169.254.169.254",  // AWS EC2 metadata
            "metadata.google.internal",  // GCP metadata
            "metadata"  // Azure metadata (via host header)
        ]
        if blocked.contains(lower) { return true }
        if lower.hasSuffix(".local") || lower.hasSuffix(".internal") { return true }
        return false
    }
    private struct IPv4Octets {
        let oct0: UInt8
        let oct1: UInt8
        let oct2: UInt8
        let oct3: UInt8
    }

    private static func parseIPv4(_ addr: String) -> IPv4Octets? {
        let parts = addr.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4,
            let oct0 = UInt8(parts[0]),
            let oct1 = UInt8(parts[1]),
            let oct2 = UInt8(parts[2]),
            let oct3: UInt8 = UInt8(parts[3])
        else { return nil }
        return IPv4Octets(oct0: oct0, oct1: oct1, oct2: oct2, oct3: oct3)
    }
}
