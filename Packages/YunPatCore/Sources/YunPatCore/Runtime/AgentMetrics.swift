import Foundation

// MARK: - Agent Metrics

/// 指标累加系统 — 单锁 + 批量快照
///
/// 所有计数器合并到一个 `Counters` struct 中，用单个 `NSLock` 保护。
/// snapshot 读路径只需一次 lock/unlock（原先 12 次）。
public final class AgentMetrics: @unchecked Sendable {

    private let lock: NSLock = NSLock()
    private var counters: Counters = Counters()
    private var startTime: Date = Date()

    private struct Counters {
        var iterationCount: Int = 0
        var toolCallCount: Int = 0
        var toolErrorCount: Int = 0
        var toolRetryCount: Int = 0
        var llmInputTokens: Int = 0
        var llmOutputTokens: Int = 0
        var stuckNudgeCount: Int = 0
        var contextCompactCount: Int = 0
        var humanApprovalCount: Int = 0
        var yieldCount: Int = 0
        var subAgentCount: Int = 0
        var subAgentErrorCount: Int = 0
        var totalLatencyMs: Double = 0.0
        var latencySampleCount: Int = 0
    }

    public init() {}

    // MARK: - Increment

    public func incIteration() {
        lock.withLock { counters.iterationCount += 1 }
    }

    public func incToolCall(method: String? = nil) {
        lock.withLock { counters.toolCallCount += 1 }
    }

    public func incToolError() {
        lock.withLock { counters.toolErrorCount += 1 }
    }

    public func incToolRetry() {
        lock.withLock { counters.toolRetryCount += 1 }
    }

    public func incStuckNudge() {
        lock.withLock { counters.stuckNudgeCount += 1 }
    }

    public func incContextCompact() {
        lock.withLock { counters.contextCompactCount += 1 }
    }

    public func incHumanApproval() {
        lock.withLock { counters.humanApprovalCount += 1 }
    }

    public func incYield() {
        lock.withLock { counters.yieldCount += 1 }
    }

    public func incSubAgent() {
        lock.withLock { counters.subAgentCount += 1 }
    }

    public func incSubAgentError() {
        lock.withLock { counters.subAgentErrorCount += 1 }
    }

    public func addInputTokens(_ count: Int) {
        guard count > 0 else { return }
        lock.withLock { counters.llmInputTokens += count }
    }

    public func addOutputTokens(_ count: Int) {
        guard count > 0 else { return }
        lock.withLock { counters.llmOutputTokens += count }
    }

    public func recordLatency(ms milliseconds: Double) {
        lock.withLock {
            counters.totalLatencyMs += milliseconds
            counters.latencySampleCount += 1
        }
    }

    // MARK: - Snapshot

    public func snapshot() -> AgentMetricsSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let elapsed: TimeInterval = Date().timeIntervalSince(startTime)
        let avgLatency: Double = counters.latencySampleCount > 0
            ? counters.totalLatencyMs / Double(counters.latencySampleCount)
            : 0
        return AgentMetricsSnapshot(
            elapsed: elapsed,
            iterationCount: counters.iterationCount,
            toolCallCount: counters.toolCallCount,
            toolErrorCount: counters.toolErrorCount,
            toolRetryCount: counters.toolRetryCount,
            llmInputTokens: counters.llmInputTokens,
            llmOutputTokens: counters.llmOutputTokens,
            stuckNudgeCount: counters.stuckNudgeCount,
            contextCompactCount: counters.contextCompactCount,
            humanApprovalCount: counters.humanApprovalCount,
            yieldCount: counters.yieldCount,
            subAgentCount: counters.subAgentCount,
            subAgentErrorCount: counters.subAgentErrorCount,
            averageLatencyMs: avgLatency
        )
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        counters = Counters()
        startTime = Date()
    }
}

// MARK: - Snapshot

public struct AgentMetricsSnapshot: Sendable, Codable, Equatable {
    public let elapsed: TimeInterval
    public let iterationCount: Int
    public let toolCallCount: Int
    public let toolErrorCount: Int
    public let toolRetryCount: Int
    public let llmInputTokens: Int
    public let llmOutputTokens: Int
    public let stuckNudgeCount: Int
    public let contextCompactCount: Int
    public let humanApprovalCount: Int
    public let yieldCount: Int
    public let subAgentCount: Int
    public let subAgentErrorCount: Int
    public let averageLatencyMs: Double
}
