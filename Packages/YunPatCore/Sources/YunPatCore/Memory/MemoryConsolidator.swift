import Foundation
import os

/// 后台记忆维护：指数衰减 → 合并 → promote → evict → prune
///
/// 规则（对齐 osaurus）：
/// - Decay: salience *= exp(-Δdays / 30)，每天微降
/// - Promote: 被最近 3+ episode 提及的事实提升 salience
/// - Evict: salience < 0.2 且 idle > 30 天 → 删除
/// - Prune: episode 保留 episodeRetentionDays 天（默认365）
///
/// consolidateLTM() 将 decay/promote/evict 合并为单次 load→mutate→save，
/// 避免重复序列化/反序列化开销。
public actor MemoryConsolidator {
    public static let shared: MemoryConsolidator = MemoryConsolidator()
    private let logger = Logger(subsystem: "com.yunpat", category: "MemoryConsolidator")
    private let store: MemoryStore
    private var lastRun: Date?
    private var isPaused: Bool = false
    public let intervalHours: Int
    public let salienceFloor: Double
    public let episodeRetentionDays: Int

    public init(
        store: MemoryStore = MemoryStore(), intervalHours: Int = 24,
        salienceFloor: Double = 0.2, episodeRetentionDays: Int = 365
    ) {
        self.store = store
        self.intervalHours = intervalHours
        self.salienceFloor = salienceFloor
        self.episodeRetentionDays = episodeRetentionDays
    }

    public func pause() { isPaused = true }

    public func resume() { isPaused = false }

    public var shouldRun: Bool {
        guard !isPaused else { return false }
        guard let last = lastRun else { return true }
        return Date().timeIntervalSince(last) >= TimeInterval(intervalHours * 3600)
    }

    public func run() async {
        lastRun = Date()
        await consolidateLTM()
        await pruneEpisodes()
    }

    // MARK: - Consolidate LTM (decay + promote + evict in one pass)

    private func consolidateLTM() async {
        var ltm: LongTermMemory = await store.loadLongTermMemory()
        let days: Double = daysSince(ltm.lastConsolidated)
        let recentEpisodes: [Episode] = await loadRecentEpisodes(count: 10)

        var mentioned: Set<String> = Set<String>()
        for episode in recentEpisodes {
            for entity in episode.entities { mentioned.insert(entity.lowercased()) }
            for topic in episode.topics { mentioned.insert(topic.lowercased()) }
        }

        let cutoff: Date = Date().addingTimeInterval(-Double(30 * 86400))

        ltm.items = ltm.items.compactMap { item in
            var salience = max(0.0, Float(Double(item.salience) * exp(-max(days, 0) / 30.0)))

            let lower = item.content.lowercased()
            let matchCount = mentioned.filter { lower.contains($0) }.count
            if matchCount >= 3 {
                salience = min(1.0, salience + 0.1)
            }

            if Double(salience) < salienceFloor && item.createdAt < cutoff {
                return nil
            }

            return MemoryItem(id: item.id, content: item.content, salience: salience, createdAt: item.createdAt)
        }

        ltm.lastConsolidated = Date()
        do {
            try await store.saveLongTermMemory(ltm)
        } catch {
            logger.error("consolidateLTM save failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Prune (旧 episode 裁切)

    private func pruneEpisodes() async {
        let db: MemoryDatabase = .shared
        let cutoff: Date = Date().addingTimeInterval(-Double(episodeRetentionDays * 86400))
        await db.deleteEpisodes(before: cutoff)
    }

    // MARK: - Helpers

    private func daysSince(_ date: Date) -> Double {
        Date().timeIntervalSince(date) / 86400
    }

    private func loadRecentEpisodes(count: Int) async -> [Episode] {
        let db: MemoryDatabase = MemoryDatabase.shared
        return await db.loadRecentEpisodes(limit: count)
    }
}
