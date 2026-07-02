import Foundation

// MARK: - Fallback Chain Entry

/// 回退链中的单个条目
public struct FallbackEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public var provider: String  // ModelProvider.rawValue
    public var model: String
    public var enabled: Bool

    public init(provider: String, model: String, enabled: Bool = true) {
        self.id = UUID()
        self.provider = provider
        self.model = model
        self.enabled = enabled
    }

    public var displayName: String {
        "\(provider) / \(model)"
    }
}

// MARK: - Fallback Chain Service

/// 管理用户配置的 LLM provider 回退链
///
/// 设计参考 Agent-main 的 FallbackChainService:
/// - 持久化到 UserDefaults
/// - 主 provider 失败时自动切换到下一个
/// - 成功时记录，连续失败数触发切换
///
/// 线程安全: @unchecked Sendable + NSLock 保护可变状态
@MainActor
public final class FallbackChainService: @unchecked Sendable {
    public static let shared: FallbackChainService = FallbackChainService()
    private let lock: NSLock = NSLock()
    private let defaults: UserDefaults
    private let storageKey: String = "yunpat.fallback.chain"
    private(set) var entries: [FallbackEntry] = []
    private(set) var currentIndex: Int = 0
    private(set) var consecutiveFailures: Int = 0

    public var failureThreshold: Int = 3

    public var hasNextProvider: Bool {
        lock.lock()
        defer { lock.unlock() }
        return nextEnabledIndex(from: currentIndex) != nil
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - CRUD

    public func add(_ entry: FallbackEntry) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
        save()
    }

    public func remove(id: UUID) {
        lock.lock()
        entries.removeAll { $0.id == id }
        if currentIndex >= entries.count { currentIndex = max(0, entries.count - 1) }
        lock.unlock()
        save()
    }

    public func update(_ entry: FallbackEntry) {
        lock.lock()
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        }
        lock.unlock()
        save()
    }

    public func reorder(_ newOrder: [FallbackEntry]) {
        lock.lock()
        entries = newOrder
        lock.unlock()
        save()
    }

    public func clear() {
        lock.lock()
        entries.removeAll()
        currentIndex = 0
        consecutiveFailures = 0
        lock.unlock()
        save()
    }

    // MARK: - Runtime Operations

    public var currentProvider: ModelProvider? {
        lock.lock()
        defer { lock.unlock() }
        guard currentIndex < entries.count else { return nil }
        return ModelProvider(rawValue: entries[currentIndex].provider)
    }

    public var currentModel: String? {
        lock.lock()
        defer { lock.unlock() }
        guard currentIndex < entries.count else { return nil }
        return entries[currentIndex].model
    }

    public func recordSuccess() {
        lock.lock()
        defer { lock.unlock() }
        consecutiveFailures = 0
    }

    public func recordFailure() -> ModelProvider? {
        lock.lock()
        consecutiveFailures += 1
        if consecutiveFailures >= failureThreshold {
            let next: ModelProvider? = switchToNext()
            lock.unlock()
            return next
        }
        let current: ModelProvider? = currentProvider
        lock.unlock()
        return current
    }

    public func switchToNext() -> ModelProvider? {
        lock.lock()
        defer { lock.unlock() }
        guard let nextIdx = nextEnabledIndex(from: currentIndex) else { return nil }
        currentIndex = nextIdx
        consecutiveFailures = 0
        guard currentIndex < entries.count else { return nil }
        return ModelProvider(rawValue: entries[currentIndex].provider)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        currentIndex = 0
        consecutiveFailures = 0
    }

    // MARK: - Summary

    public func summary() -> String {
        lock.lock()
        defer { lock.unlock() }
        if entries.isEmpty { return "（无回退链配置）" }
        var lines: [String] = []
        for (index, entry) in entries.enumerated() {
            let marker = index == currentIndex ? "→" : "  "
            let status = entry.enabled ? "✓" : "✗"
            lines.append("\(marker) [\(status)] \(entry.displayName)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func nextEnabledIndex(from current: Int) -> Int? {
        for index in (current + 1)..<entries.count where entries[index].enabled {
            return index
        }
        return nil
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        entries = (try? JSONDecoder().decode([FallbackEntry].self, from: data)) ?? []
    }

    private func save() {
        // save() is always called after lock.unlock(), so snapshot
        lock.lock()
        let snapshot: [FallbackEntry] = entries
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
