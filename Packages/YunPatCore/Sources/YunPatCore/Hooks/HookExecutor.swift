import Foundation
import os

// MARK: - Hook 执行器类型

public enum HookExecutorType: String, Codable, Sendable {
    case shell
    case http
    case agent
}

// MARK: - Hook 执行结果

public struct HookExecResult: Sendable {
    public let output: String
    public let accepted: Bool
}

// MARK: - Hook 执行器协议

public protocol HookExecuting: Sendable {
    var type: HookExecutorType { get }
    func execute(
        command: String,
        toolName: String,
        inputJSON: String,
        output: String,
        env: [String: String]
    ) async -> HookExecResult
}

// MARK: - Shell 执行器

public struct ShellHookExecutor: HookExecuting {
    public let type: HookExecutorType = .shell
    private let logger = Logger(subsystem: "com.yunpat", category: "ShellHookExecutor")

    public init() {}

    public func execute(
        command: String,
        toolName: String,
        inputJSON: String,
        output: String,
        env: [String: String]
    ) async -> HookExecResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        var processEnv: [String: String] = ProcessInfo.processInfo.environment
        processEnv["HOOK_NAME"] = ""
        processEnv["HOOK_EVENT"] = ""
        processEnv["TOOL_NAME"] = toolName
        processEnv["TOOL_INPUT"] = inputJSON
        processEnv["TOOL_OUTPUT"] = output
        for (key, value) in env { processEnv[key] = value }
        process.environment = processEnv

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            let data: Data = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                process.terminationHandler = { proc in
                    if proc.terminationStatus == 0 {
                        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                        cont.resume(returning: outputData)
                    } else {
                        cont.resume(throwing: HookError.exitCode(proc.terminationStatus))
                    }
                }
            }
            let text: String = String(data: data, encoding: .utf8) ?? ""
            let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let blocked = trimmed.hasPrefix("BLOCK:")
            return HookExecResult(
                output: blocked ? String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces) : text,
                accepted: !blocked
            )
        } catch {
            return HookExecResult(output: "Hook error: \(error.localizedDescription)", accepted: true)
        }
    }
}

// MARK: - HTTP 执行器

public struct HTTPHookExecutor: HookExecuting {
    public let type: HookExecutorType = .http
    private let logger = Logger(subsystem: "com.yunpat", category: "HTTPHookExecutor")
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func execute(
        command: String,
        toolName: String,
        inputJSON: String,
        output: String,
        env: [String: String]
    ) async -> HookExecResult {
        guard let url = URL(string: command) else {
            return HookExecResult(output: "Invalid hook URL: \(command)", accepted: true)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let payload: [String: String] = [
            "toolName": toolName,
            "input": inputJSON,
            "output": output
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response): (Data, URLResponse) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return HookExecResult(output: "Non-HTTP response", accepted: true)
            }
            let text: String = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 200 {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let blocked = trimmed.hasPrefix("BLOCK:")
                return HookExecResult(
                    output: blocked ? String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces) : text,
                    accepted: !blocked
                )
            }
            return HookExecResult(output: "HTTP \(http.statusCode): \(text)", accepted: true)
        } catch {
            return HookExecResult(output: "HTTP error: \(error.localizedDescription)", accepted: true)
        }
    }
}

// MARK: - Agent 执行器

/// Agent 执行器 — 将 Hook 命令作为 prompt 发送给子代理
///
/// 初始化时需要提供 `runAgent` 闭包，该闭包接收 prompt 字符串，返回执行结果字符串。
/// 调用方（如 AgentLoopEngine）负责将 SubAgentEngine.spawn 包装为此闭包。
public struct AgentHookExecutor: HookExecuting {
    public let type: HookExecutorType = .agent
    private let runAgent: @Sendable (String) async -> String

    public init(runAgent: @escaping @Sendable (String) async -> String) {
        self.runAgent = runAgent
    }

    public func execute(
        command: String,
        toolName: String,
        inputJSON: String,
        output: String,
        env: [String: String]
    ) async -> HookExecResult {
        let prompt: String = """
        \(command)

        Tool: \(toolName)
        Input: \(inputJSON)
        Output: \(output.hasPrefix("{") ? "[JSON payload]" : output)
        """
        let text: String = await runAgent(prompt)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let blocked = trimmed.hasPrefix("BLOCK:")
        return HookExecResult(
            output: blocked ? String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces) : text,
            accepted: !blocked
        )
    }
}

// MARK: - 错误执行器

/// 当所需执行器未配置时返回错误信息。
/// 避免静默降级（如 agent 执行器 nil 时降级为 shell 执行）。
public struct ErrorHookExecutor: HookExecuting {
    public let type: HookExecutorType = .agent
    private let message: String

    public init(message: String) {
        self.message = message
    }

    public func execute(
        command: String,
        toolName: String,
        inputJSON: String,
        output: String,
        env: [String: String]
    ) async -> HookExecResult {
        HookExecResult(output: "Hook error: \(message)", accepted: true)
    }
}
