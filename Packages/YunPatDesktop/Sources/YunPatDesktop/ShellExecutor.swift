import Foundation

public struct ShellOutput: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public actor ShellExecutor {
    private let allowedCommands: Set<String>

    public init(allowedCommands: Set<String> = ["ls", "cat", "grep", "git", "echo", "python3", "node", "swift"]) {
        self.allowedCommands = allowedCommands
    }

    public func execute(_ command: String, cwd: URL? = nil, timeout: TimeInterval = 30) async throws -> ShellOutput {
        let firstWord = command.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
        guard allowedCommands.contains(firstWord) else {
            throw ShellError.commandNotAllowed(firstWord)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        if let cwd { process.currentDirectoryURL = cwd }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if process.isRunning { process.terminate() }
        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ShellOutput(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}

public enum ShellError: Error {
    case commandNotAllowed(String)
}
