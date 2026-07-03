import Foundation

public enum RequestPriority: Sendable, Comparable {
    case low
    case normal
    case high

    public static func < (lhs: RequestPriority, rhs: RequestPriority) -> Bool {
        switch (lhs, rhs) {
        case (.low, .normal), (.low, .high), (.normal, .high): return true
        default: return false
        }
    }
}

/// 全局并发控制器 — 基于 continuation 的非忙等队列
///
/// 使用 acquire/release 模式替代 busy-wait 轮询：
/// - acquire() 在有空位时立即返回，否则挂起等待
/// - release() 唤醒最早等待的请求
/// - 跨标签协调全局并发量
public actor GlobalRequestQueue {
    public var maxConcurrentRequests: Int
    private var activeCount: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(maxConcurrentRequests: Int = 3) {
        self.maxConcurrentRequests = maxConcurrentRequests
    }

    /// 获取一个并发槽位（无空位时挂起等待）
    public func acquire() async {
        if activeCount < maxConcurrentRequests {
            activeCount += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
        activeCount += 1
    }

    /// 释放一个并发槽位（唤醒最早等待的请求）
    public func release() {
        activeCount -= 1
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        }
    }

    public func currentUsage(for provider: ModelProvider) -> Int {
        activeCount
    }
}
