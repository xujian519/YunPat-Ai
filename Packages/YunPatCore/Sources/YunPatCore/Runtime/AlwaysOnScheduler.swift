import Foundation
import os

public enum AlwaysOnTaskKind: String, Sendable, Codable, CaseIterable {
    case clipboard
    case fileWatcher
    case periodicSummary
    case memoryConsolidation
}

public enum AlwaysOnTaskState: Sendable, Codable, Equatable {
    case running
    case paused
    case error(String)
}

public struct AlwaysOnTaskStatus: Sendable {
    public let kind: AlwaysOnTaskKind
    public let state: AlwaysOnTaskState
    public let lastRun: Date?
    public let nextRun: Date?
    public let errorMessage: String?

    public init(
        kind: AlwaysOnTaskKind,
        state: AlwaysOnTaskState,
        lastRun: Date? = nil,
        nextRun: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.kind = kind
        self.state = state
        self.lastRun = lastRun
        self.nextRun = nextRun
        self.errorMessage = errorMessage
    }
}

public actor AlwaysOnScheduler {
    public static let shared = AlwaysOnScheduler()

    private let consolidator: MemoryConsolidator
    private var tasks: [AlwaysOnTaskKind: AlwaysOnTaskState] = [:]
    private var timers: [AlwaysOnTaskKind: Timer] = [:]
    private var lastRun: [AlwaysOnTaskKind: Date] = [:]
    private let logger = Logger(subsystem: "com.yunpat", category: "AlwaysOn")
    private var continuations: [UUID: AsyncStream<AlwaysOnTaskStatus>.Continuation] = [:]

    public init(consolidator: MemoryConsolidator = .shared) {
        self.consolidator = consolidator
        for kind in AlwaysOnTaskKind.allCases {
            tasks[kind] = .paused
        }
    }

    public func start(_ kind: AlwaysOnTaskKind) {
        tasks[kind] = .running
        scheduleTimer(kind)
        emit(kind)
    }

    public func stop(_ kind: AlwaysOnTaskKind) {
        tasks[kind] = .paused
        cancelTimer(kind)
        emit(kind)
    }

    public func toggle(_ kind: AlwaysOnTaskKind) {
        if tasks[kind] == .running { stop(kind) } else { start(kind) }
    }

    public func isRunning(_ kind: AlwaysOnTaskKind) -> Bool {
        tasks[kind] == .running
    }

    public func status(for kind: AlwaysOnTaskKind) -> AlwaysOnTaskStatus {
        AlwaysOnTaskStatus(
            kind: kind,
            state: tasks[kind] ?? .paused,
            lastRun: lastRun[kind],
            nextRun: nextFireDate(kind),
            errorMessage: nil
        )
    }

    public func allStatus() -> [AlwaysOnTaskStatus] {
        AlwaysOnTaskKind.allCases.map { status(for: $0) }
    }

    public func stopAll() {
        for kind in AlwaysOnTaskKind.allCases {
            stop(kind)
        }
    }

    public func startAll() {
        for kind in AlwaysOnTaskKind.allCases {
            start(kind)
        }
    }

    public nonisolated func statusStream() -> AsyncStream<AlwaysOnTaskStatus> {
        AsyncStream { continuation in
            let id = UUID()
            Task {
                await self.registerContinuation(id, continuation)
            }
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.unregisterContinuation(id)
                }
            }
        }
    }

    // MARK: - Private

    private func registerContinuation(_ id: UUID, _ cont: AsyncStream<AlwaysOnTaskStatus>.Continuation) {
        continuations[id] = cont
    }

    private func unregisterContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func scheduleTimer(_ kind: AlwaysOnTaskKind) {
        cancelTimer(kind)
        let interval: TimeInterval = interval(for: kind)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.fire(kind)
            }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        timers[kind] = timer
    }

    private func cancelTimer(_ kind: AlwaysOnTaskKind) {
        timers[kind]?.invalidate()
        timers[kind] = nil
    }

    private func fire(_ kind: AlwaysOnTaskKind) async {
        lastRun[kind] = Date()
        do {
            switch kind {
            case .periodicSummary:
                try await runPeriodicSummary()
            case .memoryConsolidation:
                await consolidator.run()
            case .clipboard, .fileWatcher:
                break
            }
            tasks[kind] = .running
        } catch {
            tasks[kind] = .error(error.localizedDescription)
            logger.error("AlwaysOn \(kind.rawValue) failed: \(error.localizedDescription)")
        }
        emit(kind)
    }

    private func runPeriodicSummary() async throws {
        guard await consolidator.shouldRun else { return }
        await consolidator.run()
    }

    private func interval(for kind: AlwaysOnTaskKind) -> TimeInterval {
        switch kind {
        case .clipboard: return 2.0
        case .fileWatcher: return 5.0
        case .periodicSummary: return 3600.0
        case .memoryConsolidation: return 21600.0
        }
    }

    private func nextFireDate(_ kind: AlwaysOnTaskKind) -> Date? {
        guard tasks[kind] == .running, let last = lastRun[kind] else { return nil }
        return last.addingTimeInterval(interval(for: kind))
    }

    private func emit(_ kind: AlwaysOnTaskKind) {
        let state = status(for: kind)
        for cont in continuations.values {
            cont.yield(state)
        }
    }
}
