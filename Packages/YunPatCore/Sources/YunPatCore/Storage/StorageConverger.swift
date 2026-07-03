import Foundation

/// 存储收敛策略 — 检测 FileVault 状态，决定 SQLite 加密姿势
///
/// 规则：
/// - FileVault ON → 明文 SQLite（依赖系统静态加密）
/// - FileVault OFF → 提示用户启用 SQLCipher 或启用 FileVault
/// - SQLCipher key 丢失 → 标 degraded，不删库，提供恢复途径
///
/// 从 struct + static let shared + mutating 改为 final class：
/// struct 单例上的 mutating 方法永远不会修改共享实例
/// （每次调用在副本上执行，副本立即销毁），等同于 silent-no-op。
/// fileVaultEnabled 使用 nonisolated(unsafe) 避免 NSLock 在 async context 的编译问题。
public final class StorageConverger: @unchecked Sendable {
    public static let shared: StorageConverger = StorageConverger()
    /// FileVault 状态缓存（由 checkFileVaultStatus 异步更新）
    public nonisolated(unsafe) private(set) var fileVaultEnabled: Bool?

    /// 当前推荐姿势（需调用 checkFileVaultStatus 后有效）
    public var recommendedPosture: StoragePosture {
        if fileVaultEnabled == true { return .plaintext }
        return .encryptedRecommended
    }

    /// 异步检查 FileVault 状态并缓存结果
    public func checkFileVaultStatus() async -> Bool {
        let task: Process = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
        task.arguments = ["status"]
        let pipe: Pipe = Pipe()
        task.standardOutput = pipe
        do { try task.run() } catch {
            print("[StorageConverger] fdesetup failed: \(error)")
            fileVaultEnabled = false
            return false
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            task.terminationHandler = { _ in continuation.resume() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output: String = String(data: data, encoding: .utf8) ?? ""
        let isOn = output.contains("FileVault is On")
        fileVaultEnabled = isOn
        return isOn
    }

    /// 数据库配置描述
    public func description(for db: DatabaseConfig) -> String {
        let posture: StoragePosture = recommendedPosture
        switch posture {
        case .plaintext:
            return "\(db.displayName): 明文 SQLite（FileVault 保护）"
        case .encryptedRecommended:
            return "\(db.displayName): 推荐启用 SQLCipher（FileVault 未开启）"
        }
    }
}

  /// 存储姿态 — 升迁（migrate）或降级（degrade）
  public enum StoragePosture: Sendable {
    case plaintext
    case encryptedRecommended
}

  /// 数据库配置 — 包含标识符和文件路径
  public struct DatabaseConfig: Sendable {
    public let name: String
    public let displayName: String
    public let path: String
    public init(name: String, displayName: String, path: String) {
        self.name = name
        self.displayName = displayName
        self.path = path
    }
}
