import Foundation

public actor CapabilityStats {
    private var latencyHistory: [String: [TimeInterval]] = [:]
    public init() {}

    public func recordLatency(_ capability: String, _ duration: TimeInterval) {
        latencyHistory[capability, default: []].append(duration)
        if latencyHistory[capability]!.count > 100 { latencyHistory[capability]!.removeFirst() }
    }

    public func averageLatency(for capability: String) -> TimeInterval? {
        guard let history = latencyHistory[capability], !history.isEmpty else { return nil }
        return history.reduce(0, +) / Double(history.count)
    }
}
