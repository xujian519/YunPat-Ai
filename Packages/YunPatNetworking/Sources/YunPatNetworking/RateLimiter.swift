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

public actor GlobalRequestQueue {
    public var maxConcurrentRequests: Int
    private var activeCount = 0

    public init(maxConcurrentRequests: Int = 3) {
        self.maxConcurrentRequests = maxConcurrentRequests
    }

    public func enqueue(
        _ request: ChatRequest,
        provider: ModelProvider,
        router: ModelRouter,
        priority: RequestPriority = .normal
    ) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        while activeCount >= maxConcurrentRequests {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        activeCount += 1
        defer { activeCount -= 1 }
        return try await router.chat(request, provider: provider)
    }

    public func currentUsage(for provider: ModelProvider) -> Int {
        activeCount
    }
}
