import AppKit
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

    // ── Clipboard 状态 ──
    private var lastClipboardChangeCount: Int = -1
    private var clipboardHistory: [String] = []
    private let clipboardHistoryMax: Int = 10

    // ── File Watcher 状态 ──
    private var watchedPaths: [String: (enabled: Bool, lastSnapshot: [String: Date])] = [:]

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

    /// 注册要监视的文件/目录路径，fileWatcher 将检测这些路径下的变化
    public func watchPaths(_ paths: [String]) {
        for path in paths {
            if watchedPaths[path] == nil {
                let snapshot = buildSnapshot(for: path)
                watchedPaths[path] = (enabled: true, lastSnapshot: snapshot)
            } else {
                watchedPaths[path]?.enabled = true
            }
        }
    }

    /// 停止监视指定路径
    public func unwatchPath(_ path: String) {
        watchedPaths[path]?.enabled = false
    }

    /// 获取剪贴板历史
    public func recentClipboardContent() -> [String] {
        Array(clipboardHistory)
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
            case .clipboard:
                runClipboardCheck()
            case .fileWatcher:
                runFileWatcherCheck()
            case .periodicSummary:
                try await runPeriodicSummary()
            case .memoryConsolidation:
                await consolidator.run()
            }
            tasks[kind] = .running
        } catch {
            tasks[kind] = .error(error.localizedDescription)
            logger.error("AlwaysOn \(kind.rawValue) failed: \(error.localizedDescription)")
        }
        emit(kind)
    }

    /// 检查剪贴板变化 — 比较 NSPasteboard changeCount
    private func runClipboardCheck() {
        let pasteboard: NSPasteboard = NSPasteboard.general
        let currentChange: Int = pasteboard.changeCount
        guard currentChange != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = currentChange

        guard let content: String = pasteboard.string(forType: .string)
            ?? pasteboard.string(forType: .rtf) else { return }
        let trimmed: String = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 去重：和最近一条相同则跳过
        if clipboardHistory.last == trimmed { return }
        clipboardHistory.append(trimmed)
        if clipboardHistory.count > clipboardHistoryMax {
            clipboardHistory.removeFirst()
        }
        logger.debug("Clipboard changed: \(trimmed.prefix(80))")
    }

    /// 检查已注册路径下的文件变化 — 比较 mtime
    private func runFileWatcherCheck() {
        for (path, config) in watchedPaths where config.enabled {
            let currentSnapshot: [String: Date] = buildSnapshot(for: path)
            let oldSnapshot: [String: Date] = config.lastSnapshot
            #if DEBUG
            // 找出新增或修改的文件
            var changes: [String] = []
            for (file, mtime) in currentSnapshot {
                if oldSnapshot[file] == nil {
                    changes.append("+\(file)")
                } else if oldSnapshot[file] != mtime {
                    changes.append("~\(file)")
                }
            }
            for file in oldSnapshot.keys where currentSnapshot[file] == nil {
                changes.append("-\(file)")
            }
            if !changes.isEmpty {
                logger.debug("File changes in \(path): \(changes.joined(separator: ", "))")
            }
            #endif
            watchedPaths[path]?.lastSnapshot = currentSnapshot
        }
    }

    /// 构建目录下文件的 mtime 快照
    private func buildSnapshot(for path: String) -> [String: Date] {
        let fileManager: FileManager = FileManager.default
        var snapshot: [String: Date] = [:]
        guard let enumerator: FileManager.DirectoryEnumerator
            = fileManager.enumerator(atPath: path) else { return snapshot }
        while let relativePath: String = enumerator.nextObject() as? String {
            let fullPath: String = (path as NSString).appendingPathComponent(relativePath)
            guard let attrs: [FileAttributeKey: Any] = try? fileManager.attributesOfItem(atPath: fullPath),
                  let fileType: FileAttributeType = attrs[.type] as? FileAttributeType,
                  fileType == .typeRegular,
                  let mtime: Date = attrs[.modificationDate] as? Date
            else { continue }
            snapshot[relativePath] = mtime
        }
        return snapshot
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
