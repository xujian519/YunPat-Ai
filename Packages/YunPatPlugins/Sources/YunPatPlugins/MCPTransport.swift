import Foundation

// MARK: - MCPTransport 协议

/// MCP 传输层抽象 — 将底层通信（stdio/HTTP/SSE/in-process）与 JSON-RPC 协议层解耦
///
/// 实现者只负责"给我 JSON-RPC bytes，返回 JSON-RPC bytes"。
/// 分帧（Content-Length / HTTP body / SSE 事件）是各实现的内部细节。
public protocol MCPTransport: Sendable {
    /// 发送 JSON-RPC payload 并等待响应
    func send(_ payload: Data) async throws -> Data
    /// 关闭传输连接
    func close() async throws
}

// MARK: - StdioMCPTransport

/// stdio 传输 — 通过子进程的 stdin/stdout 通信，Content-Length 分帧（LSP 风格）
///
/// 从 MCPClient 提取的现有逻辑，封装为独立的 MCPTransport 实现。
public final class StdioMCPTransport: MCPTransport, @unchecked Sendable {

    private let command: String
    private let args: [String]
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private let lock: NSLock = NSLock()

    public init(command: String, args: [String] = []) {
        self.command = command
        self.args = args
    }

    /// 启动子进程并建立管道
    public func start() throws {
        let proc: Process = Process()
        proc.executableURL = URL(fileURLWithPath: command.hasPrefix("/") ? command : "/usr/bin/env")
        if command.hasPrefix("/") {
            proc.arguments = args
        } else {
            proc.arguments = [command] + args
        }

        let stdin: Pipe = Pipe()
        let stdout: Pipe = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        try proc.run()

        lock.withLock {
            self.process = proc
            self.stdinPipe = stdin
            self.stdoutPipe = stdout
        }
    }

    public func send(_ payload: Data) async throws -> Data {
        let header: String = "Content-Length: \(payload.count)\r\n\r\n"
        let fullData: Data = Data(header.utf8) + payload

        guard let stdin = stdinPipe, let stdout = stdoutPipe else {
            throw MCPError(message: "StdioMCPTransport not started")
        }

        stdin.fileHandleForWriting.write(fullData)
        return try Self.readFrame(from: stdout.fileHandleForReading)
    }

    public func close() async throws {
        lock.withLock {
            process?.terminate()
            process = nil
            stdinPipe = nil
            stdoutPipe = nil
        }
    }

    // MARK: - Content-Length 分帧

    static func readFrame(from handle: FileHandle) throws -> Data {
        var header: Data = Data()
        let delimiter: Data = Data("\r\n\r\n".utf8)
        while true {
            let byte: Data = handle.readData(ofLength: 1)
            guard !byte.isEmpty else { throw MCPError(message: "Connection closed") }
            header.append(byte)
            if header.suffix(4).elementsEqual(delimiter) { break }
        }
        guard let headerStr: String = String(data: header, encoding: .utf8) else {
            throw MCPError(message: "Invalid frame header")
        }
        let length: Int = parseContentLength(headerStr)
        guard length > 0 else { throw MCPError(message: "Missing Content-Length") }
        return handle.readData(ofLength: length)
    }

    public static func parseContentLength(_ header: String) -> Int {
        for line in header.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:"),
                let value = line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
                let length = Int(value) {
                return length
            }
        }
        return 0
    }
}
