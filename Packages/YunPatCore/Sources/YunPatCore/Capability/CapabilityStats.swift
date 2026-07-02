import Foundation

public actor CapabilityStats {
    private var latencyHistory: [String: [TimeInterval]] = [:]
    public init() {}

    public func recordLatency(_ capability: String, _ duration: TimeInterval) {
        latencyHistory[capability, default: []].append(duration)
        if var history = latencyHistory[capability], history.count > 100 {
            history.removeFirst()
            latencyHistory[capability] = history
        }
    }

    public func averageLatency(for capability: String) -> TimeInterval? {
        guard let history = latencyHistory[capability], !history.isEmpty else { return nil }
        return history.reduce(0, +) / Double(history.count)
    }
}
