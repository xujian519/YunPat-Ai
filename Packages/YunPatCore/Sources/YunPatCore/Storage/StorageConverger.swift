import Foundation

/// 存储收敛策略 — 检测 FileVault 状态，决定 SQLite 加密姿势
///
/// 规则：
/// - FileVault ON → 明文 SQLite（依赖系统静态加密）
/// - FileVault OFF → 提示用户启用 SQLCipher 或启用 FileVault
/// - SQLCipher key 丢失 → 标 degraded，不删库，提供恢复途径
public struct StorageConverger: Sendable {
    public static let shared: StorageConverger = StorageConverger()
    /// FileVault 状态缓存（由 checkFileVaultStatus 异步更新）
    public private(set) var fileVaultEnabled: Bool?

    /// 当前推荐姿势（需调用 checkFileVaultStatus 后有效）
    public var recommendedPosture: StoragePosture {
        if fileVaultEnabled == true { return .plaintext }
        return .encryptedRecommended
    }

    /// 异步检查 FileVault 状态并缓存结果
    public mutating func checkFileVaultStatus() async -> Bool {
        let task: Process = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
        task.arguments = ["status"]
        let pipe: Pipe = Pipe()
        task.standardOutput = pipe
        do { try task.run() } catch {
            print("[StorageConverger] fdesetup failed: \(error)")
            self.fileVaultEnabled = false
            return false
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            task.terminationHandler = { _ in continuation.resume() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output: String = String(data: data, encoding: .utf8) ?? ""
        let isOn = output.contains("FileVault is On")
        self.fileVaultEnabled = isOn
        return isOn
    }

    /// 数据库配置描述
    public func description(for db: DatabaseConfig) -> String {
        switch recommendedPosture {
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
