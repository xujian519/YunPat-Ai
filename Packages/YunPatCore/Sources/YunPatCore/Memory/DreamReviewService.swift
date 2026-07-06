import Foundation
import os

/// Dream 模式 — 空闲时自动整理合并记忆，支持快照回滚
///
/// 行为：
/// 1. 每 6 小时触发一次（通过 AlwaysOnScheduler 调度）
/// 2. 在 consolidate 之前创建快照（序列化 LTM → JSON 快照文件）
/// 3. 合并相邻同类记忆条目，降低碎片化
/// 4. 支持 `rollback(to:)` 从快照恢复
public actor DreamReviewService {
    public static let shared = DreamReviewService()

    private let store: MemoryStore
    private let logger = Logger(subsystem: "com.yunpat", category: "DreamReview")
    private let snapshotDir: URL
    private var snapshots: [DreamSnapshot] = []

    public struct DreamSnapshot: Sendable, Codable {
        public let id: UUID
        public let createdAt: Date
        public let label: String
        public let ltmSnapshot: LongTermMemory

        public init(label: String, ltm: LongTermMemory) {
            self.id = UUID()
            self.createdAt = Date()
            self.label = label
            self.ltmSnapshot = ltm
        }
    }

    public init(store: MemoryStore = .init()) {
        self.store = store
        let dir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.yunpat/dream_snapshots")
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("yunpat_dream_snapshots")
        self.snapshotDir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// 执行一次 Dream 整理
    public func run() async {
        let before: LongTermMemory = await store.loadLongTermMemory()
        let snapshot: DreamSnapshot = DreamSnapshot(
            label: "pre_dream_\(ISO8601DateFormatter().string(from: Date()))",
            ltm: before
        )
        await saveSnapshot(snapshot)

        var after: LongTermMemory = before
        after.items = mergeAdjacent(after.items)
        do {
            try await store.saveLongTermMemory(after)
            logger.notice("Dream review complete: \(before.items.count) → \(after.items.count) items")
        } catch {
            logger.error("Dream save failed: \(error.localizedDescription)")
        }
    }

    /// 列出可用快照
    public func listSnapshots() -> [DreamSnapshot] {
        if snapshots.isEmpty { loadSnapshots() }
        return snapshots.sorted { $0.createdAt > $1.createdAt }
    }

    /// 回滚到指定快照
    public func rollback(to snapshotID: UUID) async throws {
        guard let snap = snapshots.first(where: { $0.id == snapshotID }) else {
            throw DreamError.snapshotNotFound
        }
        try await store.saveLongTermMemory(snap.ltmSnapshot)
        logger.notice("Rolled back to snapshot \(snap.label)")
    }

    /// 删除旧快照（保留最近 N 个）
    public func pruneSnapshots(keepLast: Int = 10) {
        guard snapshots.count > keepLast else { return }
        let toDelete = snapshots.sorted { $0.createdAt > $1.createdAt }.dropFirst(keepLast)
        for snap in toDelete {
            deleteSnapshotFile(snap)
        }
        snapshots = Array(snapshots.sorted { $0.createdAt > $1.createdAt }.prefix(keepLast))
    }

    // MARK: - Private

    private func mergeAdjacent(_ items: [MemoryItem]) -> [MemoryItem] {
        guard items.count > 1 else { return items }
        var merged: [MemoryItem] = []
        var index: Int = 0
        while index < items.count {
            var combined: MemoryItem = items[index]
            var nextIdx: Int = index + 1
            while nextIdx < items.count {
                if isSimilar(combined.content, items[nextIdx].content) {
                    combined = MemoryItem(
                        id: combined.id,
                        content: "\(combined.content)\n---\n\(items[nextIdx].content)",
                        salience: max(combined.salience, items[nextIdx].salience),
                        createdAt: combined.createdAt
                    )
                    nextIdx += 1
                } else {
                    break
                }
            }
            merged.append(combined)
            index = nextIdx
        }
        return merged
    }

    private func isSimilar(_ first: String, _ second: String) -> Bool {
        let aWords = Set(first.lowercased().split(separator: " ").map(String.init))
        let bWords = Set(second.lowercased().split(separator: " ").map(String.init))
        guard !aWords.isEmpty, !bWords.isEmpty else { return false }
        let intersection = aWords.intersection(bWords)
        return Double(intersection.count) / Double(min(aWords.count, bWords.count)) > 0.5
    }

    private func saveSnapshot(_ snapshot: DreamSnapshot) async {
        let url = snapshotDir.appendingPathComponent("\(snapshot.id.uuidString).json")
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url)
        snapshots.append(snapshot)
    }

    private func loadSnapshots() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: snapshotDir, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let snap = try? JSONDecoder().decode(DreamSnapshot.self, from: data)
            else { continue }
            snapshots.append(snap)
        }
    }

    private func deleteSnapshotFile(_ snapshot: DreamSnapshot) {
        let url = snapshotDir.appendingPathComponent("\(snapshot.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}

public enum DreamError: Error, LocalizedError {
    case snapshotNotFound

    public var errorDescription: String? {
        switch self {
        case .snapshotNotFound: return "快照未找到"
        }
    }
}
