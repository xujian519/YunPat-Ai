import Foundation

public struct VersionInfo: Sendable {
    public let hash: String
    public let message: String
    public let timestamp: Date
    public let author: String

    public init(hash: String, message: String, timestamp: Date, author: String) {
        self.hash = hash
        self.message = message
        self.timestamp = timestamp
        self.author = author
    }
}

/// Dual-track version control: Git as primary, TimeMachine snapshots as optional safety net.
public actor VersionController {
    private let workspaceRoot: URL
    private let shell: ShellExecutor

    public init(workspaceRoot: URL, shell: ShellExecutor = ShellExecutor()) {
        self.workspaceRoot = workspaceRoot
        self.shell = shell
    }

    // MARK: - Git operations

    public func gitInit() async throws {
        _ = try await shell.execute("git init", cwd: workspaceRoot)
    }

    public func gitStatus() async throws -> String {
        let output: ShellOutput = try await shell.execute("git status --porcelain", cwd: workspaceRoot)
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func stageAll() async throws {
        _ = try await shell.execute("git add -A", cwd: workspaceRoot)
    }

    public func commit(_ message: String) async throws {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        _ = try await shell.execute("git commit -m \"\(escaped)\"", cwd: workspaceRoot)
    }

    public func log(limit: Int = 10) async throws -> [VersionInfo] {
        let cmd: String = "git log --format='%H|%s|%aI|%an' -\(limit)"
        let output: ShellOutput = try await shell.execute(cmd, cwd: workspaceRoot)
        let lines: [String] = output.stdout
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        return lines.compactMap(VersionController.parseLogLine)
    }

    // MARK: - TimeMachine snapshots (best-effort)

    /// Attempt a TimeMachine local snapshot. This is a no-op if tmutil is unavailable
    /// or the process lacks permissions.
    @discardableResult
    public func timeMachineSnapshot() async throws -> Bool {
        let cmd: String = "tmutil localsnapshot / 2>/dev/null"
        let output: ShellOutput = try await shell.execute(cmd, cwd: workspaceRoot, timeout: 10)
        return output.exitCode == 0
    }

    /// Creates a version checkpoint: Git commit with optional TimeMachine snapshot.
    public func createCheckpoint(_ label: String) async throws {
        try await stageAll()
        try await commit("checkpoint: \(label)")
        _ = try? await timeMachineSnapshot()
    }

    // MARK: - Private helpers

    private static func parseLogLine(_ line: String) -> VersionInfo? {
        let parts: [String] = line.components(separatedBy: "|")
        guard parts.count >= 4 else { return nil }
        let hash: String = parts[0]
        let message: String = parts[1]
        let author: String = parts[3]
        let formatter: ISO8601DateFormatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp =
            formatter.date(from: parts[2])
            ?? ISO8601DateFormatter().date(from: parts[2])
            ?? Date()
        return VersionInfo(hash: hash, message: message, timestamp: timestamp, author: author)
    }
}
