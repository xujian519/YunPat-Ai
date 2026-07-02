import Foundation

// MARK: - File Snapshot Store

/// 文件快照与 Diff 管理
///
/// 设计参考 Agent-main 的 DiffStore + FileBackupService:
/// - UUID 管理 diff: create → store → apply → undo
/// - 自动快照: 每次 write_file/edit_file 前保存原文件
/// - 撤销栈: 每个文件维护 appliedDiffs 栈，支持 lastAppliedDiffId
/// - 快照目录: ~/Documents/YunPat/snapshots/<hash>/
///
/// 专利场景适配: 反复修改权利要求时，可回退到任意历史版本
public final class FileSnapshotStore: @unchecked Sendable {
    public static let shared: FileSnapshotStore = FileSnapshotStore()
    private let lock: NSLock = NSLock()
    /// 快照根目录
    public static let snapshotDir: URL = {
        let home: URL = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Documents/YunPat/snapshots")
    }()

    /// diff 存储: [UUID: (diff: String, source: String)]
    private var diffs: [UUID: DiffEntry] = [:]
    /// 文件路径 → 已应用 diff 的 UUID 栈
    private var appliedDiffs: [String: [UUID]] = [:]
    /// 文件路径 → 原始内容 (编辑前快照)
    private var originalContents: [String: String] = [:]

    private init() {
        try? FileManager.default.createDirectory(at: Self.snapshotDir, withIntermediateDirectories: true)
    }

    // MARK: - Snapshot (Auto-backup before write)

    /// 编辑前保存原始文件内容，返回快照路径
    @discardableResult
    public func snapshot(filePath: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return nil }

        // 计算内容哈希作为快照标识
        let hash = stableHash(content)

        // 保存到快照目录
        let snapshotPath: String = Self.snapshotDir
            .appendingPathComponent(hash)
            .appendingPathExtension("snapshot")
            .path

        if !FileManager.default.fileExists(atPath: snapshotPath) {
            try? content.write(toFile: snapshotPath, atomically: true, encoding: .utf8)
        }

        // 记录原始内容 (每个文件只保留最后一次快照前的内容)
        originalContents[filePath] = content

        return snapshotPath
    }

    /// 恢复文件到快照状态
    public func restore(filePath: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let original = originalContents[filePath] else { return false }
        do {
            try original.write(toFile: filePath, atomically: true, encoding: .utf8)
            originalContents.removeValue(forKey: filePath)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Diff Store

    /// 存储 diff，返回 UUID key
    public func store(diff: String, source: String) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let id: UUID = UUID()
        diffs[id] = DiffEntry(diff: diff, source: source)
        return id
    }

    /// 获取存储的 diff
    public func retrieve(_ id: UUID) -> (diff: String, source: String)? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = diffs[id] else { return nil }
        return (entry.diff, entry.source)
    }

    /// 记录 diff 已应用到文件
    public func recordApply(diffId: UUID, filePath: String) {
        lock.lock()
        defer { lock.unlock() }
        appliedDiffs[filePath, default: []].append(diffId)
    }

    /// 获取文件最后应用的 diff ID (用于 undo)
    public func lastAppliedDiffId(for filePath: String) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        return appliedDiffs[filePath]?.last
    }

    /// 撤销: 弹出最后应用的 diff
    public func popLastApplied(for filePath: String) {
        lock.lock()
        defer { lock.unlock() }
        appliedDiffs[filePath]?.removeLast()
    }

    /// 文件修改后使相关 diff 失效
    public func invalidateDiffs(for filePath: String) {
        lock.lock()
        defer { lock.unlock() }
        // 清除此文件的 appliedDiffs 和原始内容
        appliedDiffs.removeValue(forKey: filePath)
        originalContents.removeValue(forKey: filePath)
    }

    // MARK: - Clear

    /// 任务开始前清空
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        diffs.removeAll()
        appliedDiffs.removeAll()
        originalContents.removeAll()
    }

    /// 获取文件当前是否有快照
    public func hasSnapshot(for filePath: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return originalContents[filePath] != nil
    }

    // MARK: - Helpers

    /// 简单内容哈希 (文件名安全)
    private func stableHash(_ content: String) -> String {
        let data: Data = Data(content.utf8)
        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - Diff Entry

private struct DiffEntry: Sendable {
    let diff: String
    let source: String
}
