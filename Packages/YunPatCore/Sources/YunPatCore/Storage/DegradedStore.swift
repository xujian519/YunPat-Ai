import Foundation

/// Keychain 失效时标记 degraded，不删库，提供恢复
///
/// 数据库 KEY 丢失 → 数据库文件仍保留，标记 degraded
/// 用户可通过重试或重置恢复
public actor DegradedStore {
    public static let shared: DegradedStore = DegradedStore()
    private var degraded: [String: DegradedReason] = [:]

    private init() {}

    /// 标记数据库为 degraded
    public func markDegraded(_ dbId: String, reason: DegradedReason) {
        degraded[dbId] = reason
    }

    /// 解除 degraded 状态
    public func clearDegraded(_ dbId: String) {
        degraded.removeValue(forKey: dbId)
    }

    /// 查询 degraded 状态
    public func isDegraded(_ dbId: String) -> Bool {
        degraded.keys.contains(dbId)
    }

    /// 获取 diagnostic 信息
    public func diagnostics(for dbId: String) -> DegradedDiagnostics {
        guard let reason = degraded[dbId] else {
            return DegradedDiagnostics(
                dbId: dbId, status: .healthy,
                message: "数据库正常",
                canRetry: false, canReset: false
            )
        }
        return DegradedDiagnostics(
            dbId: dbId, status: .degraded(reason),
            message: reason.message,
            canRetry: reason.retryable,
            canReset: reason.resettable
        )
    }

    /// 获取所有 degraded 状态
    public func allDegraded() -> [(String, DegradedReason)] {
        degraded.map { ($0.key, $0.value) }
    }

    /// 清空所有
    public func reset() {
        degraded.removeAll()
    }
}

// MARK: - Types

/// 数据库降级原因 — 密钥丢失或 Keychain 不可用
public enum DegradedReason: Sendable {
    case keyNotFound(String)
    case keychainUnavailable(String)
    case decryptionFailed(String)
    case unknown(String)

    public var message: String {
        switch self {
        case .keyNotFound(let db): return "无法找到 \(db) 的加密密钥。如果密钥已丢失，可重置数据库。"
        case .keychainUnavailable: return "Keychain 不可用，通常发生在未解锁或沙盒环境中。"
        case .decryptionFailed(let db): return "\(db) 解密失败。数据可能已损坏或密钥不匹配。"
        case .unknown(let detail): return "未知错误: \(detail)"
        }
    }

    public var retryable: Bool {
        if case .keychainUnavailable = self { return true }
        if case .keyNotFound = self { return false }
        return false
    }

    public var resettable: Bool {
        if case .keyNotFound = self { return true }
        if case .decryptionFailed = self { return true }
        return false
    }
}

  /// 降级诊断信息 — 状态、消息及恢复方案
  public struct DegradedDiagnostics: Sendable {
    public let dbId: String
    public let status: DatabaseStatus
    public let message: String
    public let canRetry: Bool
    public let canReset: Bool

    public init(dbId: String, status: DatabaseStatus, message: String, canRetry: Bool, canReset: Bool) {
        self.dbId = dbId
        self.status = status
        self.message = message
        self.canRetry = canRetry
        self.canReset = canReset
    }
}

  /// 数据库状态 — healthy 或 degraded
  public enum DatabaseStatus: Sendable {
    case healthy
    case degraded(DegradedReason)
}
