import CryptoKit
import Foundation

// MARK: - Tier 数据清单模型

/// 数据分层 — T1（核心）/ T2（常用）/ T3（扩展）
public enum DataTier: String, Codable, Sendable {
    case tier1 = "T1"
    case tier2 = "T2"
    case tier3 = "T3"
}

/// 分层文件条目 — 路径、SHA256 校验和及大小
public struct TierFileEntry: Codable, Sendable {
    public let path: String
    public let sha256: String
    public let size: Int
    public init(path: String, sha256: String, size: Int) {
        self.path = path
        self.sha256 = sha256
        self.size = size
    }
}

public struct TierManifest: Codable, Sendable {
    public let version: String
    public let tier: DataTier
    public let totalFileCount: Int
    public let totalSizeBytes: Int
    public let files: [TierFileEntry]
    public init(version: String, tier: DataTier, files: [TierFileEntry]) {
        self.version = version
        self.tier = tier
        self.totalFileCount = files.count
        self.totalSizeBytes = files.reduce(0) { $0 + $1.size }
        self.files = files
    }
}

public struct VerificationResult: Sendable {
    public let valid: Bool
    public let missingFiles: [String]
    public let corruptedFiles: [String]
    public let totalSizeBytes: Int
    public let strategy: VerificationStrategy
    public enum VerificationStrategy: String, Sendable {
        case full
        case sampling
        case skipped
    }
    public init(
        valid: Bool, missingFiles: [String], corruptedFiles: [String],
        totalSizeBytes: Int, strategy: VerificationStrategy
    ) {
        self.valid = valid
        self.missingFiles = missingFiles
        self.corruptedFiles = corruptedFiles
        self.totalSizeBytes = totalSizeBytes
        self.strategy = strategy
    }
}

public actor TierVerifier {
    private let versionKey: String = "YunPat.LastVerifiedVersion"
    private static let sampleInterval: Int = 10
    public init() {}

    public func verify(tier: DataTier, dataRoot: URL, manifestURL: URL) async -> VerificationResult {
        guard let data = try? Data(contentsOf: manifestURL),
            let manifest: TierManifest = try? JSONDecoder().decode(TierManifest.self, from: data)
        else {
            return VerificationResult(
                valid: false, missingFiles: [], corruptedFiles: [],
                totalSizeBytes: 0, strategy: .skipped)
        }

        let lastVersion: String = UserDefaults.standard.string(forKey: versionKey) ?? ""
        let needsFull: Bool = lastVersion != manifest.version
        let strategy: VerificationResult.VerificationStrategy = needsFull ? .full : .sampling

        let filesToCheck: [TierFileEntry] =
            needsFull
            ? manifest.files
            : manifest.files.enumerated().filter { $0.offset % Self.sampleInterval == 0 }.map { $0.element }

        var missing: [String] = []
        var corrupted: [String] = []
        var totalSize: Int = 0
        for entry in filesToCheck {
            let fileURL = dataRoot.appendingPathComponent(entry.path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                missing.append(entry.path)
                continue
            }
            guard let fileData = try? Data(contentsOf: fileURL) else {
                corrupted.append(entry.path)
                continue
            }
            let hash = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()
            if hash != entry.sha256 { corrupted.append(entry.path) }
            totalSize += fileData.count
        }

        if needsFull, missing.isEmpty, corrupted.isEmpty {
            UserDefaults.standard.set(manifest.version, forKey: versionKey)
        }

        return VerificationResult(
            valid: missing.isEmpty && corrupted.isEmpty,
            missingFiles: missing, corruptedFiles: corrupted,
            totalSizeBytes: totalSize, strategy: strategy)
    }

    public func generateManifest(
        version: String, tier: DataTier,
        root: URL, paths: [String]
    ) async throws -> TierManifest {
        var entries: [TierFileEntry] = []
        for path in paths {
            let data: Data = try Data(contentsOf: root.appendingPathComponent(path))
            let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            entries.append(TierFileEntry(path: path, sha256: hash, size: data.count))
        }
        return TierManifest(version: version, tier: tier, files: entries)
    }

    public func resetVersionCache() {
        UserDefaults.standard.removeObject(forKey: versionKey)
    }
}
