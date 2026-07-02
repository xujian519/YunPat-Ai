import Foundation

// MARK: - Agent Metrics

/// 对标 Tokio `runtime/metrics/` 的锁保护指标累加系统
///
/// 每个指标使用独立 `NSLock` 保护，避免锁竞争。
/// 快照操作批量读取所有指标，返回不可变的 `AgentMetricsSnapshot`。
///
/// ## 设计参考
///
/// Tokio `runtime/metrics/batch.rs`：per-worker 无锁累加，聚合时批量读取。
/// Swift 中 `NSLock` 替代 `AtomicUsize`，语义等价但跨平台兼容。
///
/// ## 线程安全
///
/// `@unchecked Sendable` — 所有内部状态由 `NSLock` 保护，
/// 因此跨 Sendable 边界是安全的。
public final class AgentMetrics: @unchecked Sendable {

    // Per-metric locks — each counter is independently lockable,
    // preventing contention between counter updates.
    private let _iterationCount: NSLock = NSLock()
    private var _iterationCount_value: Int = 0
    private let _toolCallCount: NSLock = NSLock()
    private var _toolCallCount_value: Int = 0
    private let _toolErrorCount: NSLock = NSLock()
    private var _toolErrorCount_value: Int = 0
    private let _toolRetryCount: NSLock = NSLock()
    private var _toolRetryCount_value: Int = 0
    private let _llmInputTokens: NSLock = NSLock()
    private var _llmInputTokens_value: Int = 0
    private let _llmOutputTokens: NSLock = NSLock()
    private var _llmOutputTokens_value: Int = 0
    private let _stuckNudgeCount: NSLock = NSLock()
    private var _stuckNudgeCount_value: Int = 0
    private let _contextCompactCount: NSLock = NSLock()
    private var _contextCompactCount_value: Int = 0
    private let _humanApprovalCount: NSLock = NSLock()
    private var _humanApprovalCount_value: Int = 0
    private let _yieldCount: NSLock = NSLock()
    private var _yieldCount_value: Int = 0
    private let _subAgentCount: NSLock = NSLock()
    private var _subAgentCount_value: Int = 0
    private let _subAgentErrorCount: NSLock = NSLock()
    private var _subAgentErrorCount_value: Int = 0

    private let _startTime: NSLock = NSLock()
    private var _startTime_value: Date = Date()
    private let _totalLatencyMs: NSLock = NSLock()
    private var _totalLatencyMs_value: Double = 0.0
    private let _latencySampleCount: NSLock = NSLock()
    private var _latencySampleCount_value: Int = 0

    // MARK: - Increment

    public func incIteration() { _iterationCount.withLock { _iterationCount_value += 1 } }
    public func incToolCall() { _toolCallCount.withLock { _toolCallCount_value += 1 } }
    public func incToolError() { _toolErrorCount.withLock { _toolErrorCount_value += 1 } }
    public func incToolRetry() { _toolRetryCount.withLock { _toolRetryCount_value += 1 } }
    public func incStuckNudge() { _stuckNudgeCount.withLock { _stuckNudgeCount_value += 1 } }
    public func incContextCompact() { _contextCompactCount.withLock { _contextCompactCount_value += 1 } }
    public func incHumanApproval() { _humanApprovalCount.withLock { _humanApprovalCount_value += 1 } }
    public func incYield() { _yieldCount.withLock { _yieldCount_value += 1 } }
    public func incSubAgent() { _subAgentCount.withLock { _subAgentCount_value += 1 } }
    public func incSubAgentError() { _subAgentErrorCount.withLock { _subAgentErrorCount_value += 1 } }

    public func addInputTokens(_ count: Int) {
        guard count > 0 else { return }
        _llmInputTokens.withLock { _llmInputTokens_value += count }
    }
    public func addOutputTokens(_ count: Int) {
        guard count > 0 else { return }
        _llmOutputTokens.withLock { _llmOutputTokens_value += count }
    }

    public func recordLatency(ms milliseconds: Double) {
        _totalLatencyMs.withLock { _totalLatencyMs_value += milliseconds }
        _latencySampleCount.withLock { _latencySampleCount_value += 1 }
    }

    // MARK: - Snapshot

    public func snapshot() -> AgentMetricsSnapshot {
        AgentMetricsSnapshot(
            elapsed: Date().timeIntervalSince(_startTime.withLock { _startTime_value }),
            iterationCount: _iterationCount.withLock { _iterationCount_value },
            toolCallCount: _toolCallCount.withLock { _toolCallCount_value },
            toolErrorCount: _toolErrorCount.withLock { _toolErrorCount_value },
            toolRetryCount: _toolRetryCount.withLock { _toolRetryCount_value },
            llmInputTokens: _llmInputTokens.withLock { _llmInputTokens_value },
            llmOutputTokens: _llmOutputTokens.withLock { _llmOutputTokens_value },
            stuckNudgeCount: _stuckNudgeCount.withLock { _stuckNudgeCount_value },
            contextCompactCount: _contextCompactCount.withLock { _contextCompactCount_value },
            humanApprovalCount: _humanApprovalCount.withLock { _humanApprovalCount_value },
            yieldCount: _yieldCount.withLock { _yieldCount_value },
            subAgentCount: _subAgentCount.withLock { _subAgentCount_value },
            subAgentErrorCount: _subAgentErrorCount.withLock { _subAgentErrorCount_value },
            averageLatencyMs: {
                let sampleCount: Int = _latencySampleCount.withLock { _latencySampleCount_value }
                let totalLatency: Double = _totalLatencyMs.withLock { _totalLatencyMs_value }
                return sampleCount > 0 ? totalLatency / Double(sampleCount) : 0
            }()
        )
    }

    public func reset() {
        _iterationCount.withLock { _iterationCount_value = 0 }
        _toolCallCount.withLock { _toolCallCount_value = 0 }
        _toolErrorCount.withLock { _toolErrorCount_value = 0 }
        _toolRetryCount.withLock { _toolRetryCount_value = 0 }
        _llmInputTokens.withLock { _llmInputTokens_value = 0 }
        _llmOutputTokens.withLock { _llmOutputTokens_value = 0 }
        _stuckNudgeCount.withLock { _stuckNudgeCount_value = 0 }
        _contextCompactCount.withLock { _contextCompactCount_value = 0 }
        _humanApprovalCount.withLock { _humanApprovalCount_value = 0 }
        _yieldCount.withLock { _yieldCount_value = 0 }
        _subAgentCount.withLock { _subAgentCount_value = 0 }
        _subAgentErrorCount.withLock { _subAgentErrorCount_value = 0 }
        _totalLatencyMs.withLock { _totalLatencyMs_value = 0 }
        _latencySampleCount.withLock { _latencySampleCount_value = 0 }
        _startTime.withLock { _startTime_value = Date() }
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
