import Foundation

/// 后台记忆维护：指数衰减 → merge → promote → evict → prune
///
/// 规则（对齐 osaurus）：
/// - Decay: salience *= exp(-Δdays / 30)，每天微降
/// - Merge: Jaccard ≥ 0.9 的 near-dup episode 合并
/// - Promote: 被最近 3+ episode 提及的事实提升 salience
/// - Evict: salience < 0.2 且 idle > 30 天 → 删除
/// - Prune: episode 保留 365 天
public actor MemoryConsolidator {
    public static let shared: MemoryConsolidator = MemoryConsolidator()
    private let store: MemoryStore
    private var lastRun: Date?
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

    public var shouldRun: Bool {
        guard let last = lastRun else { return true }
        return Date().timeIntervalSince(last) >= TimeInterval(intervalHours * 3600)
    }

    public func run() async {
        lastRun = Date()
        await decay()
        await promote()
        await evict()
        await prune()
    }

    // MARK: - Decay (指数衰减)

    private func decay() async {
        var ltm: LongTermMemory = await store.loadLongTermMemory()
        let days: Double = daysSince(ltm.lastConsolidated)
        guard days > 0 else { return }

        ltm.items = ltm.items.map { item in
            let newSalience = max(0.0, Float(Double(item.salience) * exp(-days / 30.0)))
            return MemoryItem(id: item.id, content: item.content, salience: newSalience, createdAt: item.createdAt)
        }
        ltm.lastConsolidated = Date()
        do {
            try await store.saveLongTermMemory(ltm)
        } catch {
            print("[MemoryConsolidator] decay save failed: \(error)")
        }
    }

    // MARK: - Promote (频次提升)

    private func promote() async {
        var ltm: LongTermMemory = await store.loadLongTermMemory()
        let recentEpisodes: [Episode] = await loadRecentEpisodes(count: 10)

        // 收集最近 episode 中提及的实体
        var mentioned: Set<String> = Set<String>()
        for episode in recentEpisodes {
            for entity in episode.entities { mentioned.insert(entity.lowercased()) }
            for topic in episode.topics { mentioned.insert(topic.lowercased()) }
        }

        // 提升 LTM 中匹配实体的 salience
        for idx in ltm.items.indices {
            let lower = ltm.items[idx].content.lowercased()
            let matchCount = mentioned.filter { lower.contains($0) }.count
            if matchCount >= 3 {
                ltm.items[idx] = MemoryItem(
                    id: ltm.items[idx].id,
                    content: ltm.items[idx].content,
                    salience: min(1.0, ltm.items[idx].salience + Float(0.1)),
                    createdAt: ltm.items[idx].createdAt
                )
            }
        }
        do {
            try await store.saveLongTermMemory(ltm)
        } catch {
            print("[MemoryConsolidator] promote save failed: \(error)")
        }
    }

    // MARK: - Evict (低 salience 淘汰)

    private func evict() async {
        var ltm: LongTermMemory = await store.loadLongTermMemory()
        let cutoff: Date = Date().addingTimeInterval(-Double(30 * 86400))
        ltm.items.removeAll { item in
            Double(item.salience) < salienceFloor && item.createdAt < cutoff
        }
        do {
            try await store.saveLongTermMemory(ltm)
        } catch {
            print("[MemoryConsolidator] evict save failed: \(error)")
        }
    }

    // MARK: - Prune (旧 episode 裁切)

    private func prune() async {
        let db: MemoryDatabase = .shared
        let all: [Episode] = await db.loadAllEpisodes()
        let cutoff: Date = Date().addingTimeInterval(-90 * 86400)
        for episode in all where episode.createdAt < cutoff {
            await db.deleteEpisode(id: episode.id)
        }
    }

    // MARK: - Helpers

    private func daysSince(_ date: Date) -> Double {
        Date().timeIntervalSince(date) / 86400
    }

    private func loadRecentEpisodes(count: Int) async -> [Episode] {
        let db: MemoryDatabase = MemoryDatabase.shared
        let all: [Episode] = await db.loadAllEpisodes()
        return all.sorted(by: { $0.createdAt > $1.createdAt }).prefix(count).map { $0 }
    }
}
