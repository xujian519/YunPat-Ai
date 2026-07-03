import Foundation

// MARK: - Enhanced Hook Events

/// Hook 事件类型枚举 — preToolUse / postToolUse / taskStart / taskComplete / buildFailure
public enum HookEvent: String, CaseIterable, Codable, Sendable {
    case preToolUse  // 工具执行前 — 可 block
    case postToolUse  // 工具执行后 — 可 transform 输出
    case taskStart  // 任务开始
    case taskComplete  // 任务完成
    case buildFailure  // 构建失败
}

/// Hook 决策 — 允许（allow）或阻止（block）工具调用
public enum HookDecision: String, Sendable {
    case allow  // 允许执行
    case block  // 阻止，返回 message 作为替代结果
}

/// Hook 执行错误 — exitCode 等运行时错误
public enum HookError: Error, Sendable {
    case exitCode(Int32)
}

// MARK: - Hook Rule

/// Hook 规则 — 按事件类型和工具名匹配，执行 Shell 命令
public struct HookRule: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var event: HookEvent

    /// 工具名称匹配模式 (空 = 匹配所有)。支持 `*` 通配符前缀匹配。
    public var toolPattern: String

    /// Shell 命令 — 接收 TOOL_NAME / TOOL_INPUT / TOOL_OUTPUT 环境变量
    public var command: String

    public var enabled: Bool

    public init(
        name: String,
        event: HookEvent,
        toolPattern: String = "",
        command: String,
        enabled: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.event = event
        self.toolPattern = toolPattern
        self.command = command
        self.enabled = enabled
    }

    /// 检查是否匹配指定工具名
    public func matches(toolName: String) -> Bool {
        guard enabled else { return false }
        if toolPattern.isEmpty { return true }
        if toolPattern.hasSuffix("*") {
            let prefix = String(toolPattern.dropLast())
            return toolName.hasPrefix(prefix)
        }
        return toolName == toolPattern
    }
}

// MARK: - Sendable-safe Tool Input

/// Sendable 安全包装器 — 用于跨 actor 传递 JSON 兼容的 [String: Any] 字典
public struct ToolInput: @unchecked Sendable {
    public let raw: [String: Any]
    public init(_ raw: [String: Any]) { self.raw = raw }
}

// MARK: - Hooks Service

/// 增强版 Hooks 服务
///
/// 设计参考 Agent-main 的 HooksService:
/// - preToolUse 可 block 工具调用
/// - postToolUse 可 transform 输出
/// - Shell 命令执行，env 变量注入 (TOOL_NAME/TOOL_INPUT/TOOL_OUTPUT)
/// - 持久化到 ~/Documents/YunPat/hooks.json
///
/// 线程安全: 从 class + NSLock 迁移为 actor，利用 Swift 6 原生并发隔离。
/// 所有 mutable 状态由 actor 串行队列保护，无需显式锁。
public actor HooksService {
    public static let shared: HooksService = HooksService()
    private(set) var rules: [HookRule] = []
    private let fileURL: URL

    private init() {
        let home: URL = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Documents/YunPat")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("[HooksService] Failed to create hooks directory: \(error)")
        }
        self.fileURL = dir.appendingPathComponent("hooks.json")
        if let data = try? Data(contentsOf: fileURL) {
            do {
                self.rules = try JSONDecoder().decode([HookRule].self, from: data)
            } catch {
                print("[HooksService] Failed to decode hooks.json: \(error)")
                self.rules = []
            }
        }
    }

    // MARK: - CRUD

    /// 添加一条 Hook 规则并持久化
    public func add(_ rule: HookRule) {
        rules.append(rule)
        save()
    }

    /// 删除指定 ID 的 Hook 规则并持久化
    public func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    /// 更新 Hook 规则并持久化
    public func update(_ rule: HookRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
            save()
        }
    }

    /// 切换 Hook 规则的启用/禁用状态并持久化
    public func toggle(id: UUID) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].enabled.toggle()
            save()
        }
    }

    // MARK: - Execution

    /// 执行所有匹配的 pre-tool hooks，返回是否允许执行
    public func runPreToolHooks(toolName: String, input: ToolInput) async -> (decision: HookDecision, message: String?)
    {  // swiftlint:disable:this opening_brace
        let snapshot: [HookRule] = rules
        for rule in snapshot where rule.event == .preToolUse && rule.matches(toolName: toolName) {
            let output: String = await executeHook(rule, toolName: toolName, input: input.raw)
            let trimmed: String = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("BLOCK:") {
                let msg: String = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                return (.block, msg.isEmpty ? "Blocked by hook '\(rule.name)'" : msg)
            }
        }
        return (.allow, nil)
    }

    /// 执行所有匹配的 post-tool hooks，返回可能被转换的输出
    public func runPostToolHooks(toolName: String, input: ToolInput, output: String) async -> String? {
        let snapshot: [HookRule] = rules
        var transformed: String = output
        for rule in snapshot where rule.event == .postToolUse && rule.matches(toolName: toolName) {
            let result: String = await executeHook(rule, toolName: toolName, input: input.raw, output: output)
            let trimmed: String = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                transformed = trimmed
            }
        }
        return transformed != output ? transformed : nil
    }

    /// 执行指定事件类型的所有 Hook
    public func runEventHooks(_ event: HookEvent, context: [String: String] = [:]) async {
        let snapshot: [HookRule] = rules
        for rule in snapshot where rule.event == event && rule.enabled {
            _ = await executeHook(rule, toolName: "", input: [:], output: "", env: context)
        }
    }

    // MARK: - Shell Execution

    private func executeHook(
        _ rule: HookRule,
        toolName: String,
        input: [String: Any],
        output: String = "",
        env: [String: String] = [:]
    ) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", rule.command]

        var processEnv: [String: String] = ProcessInfo.processInfo.environment
        processEnv["HOOK_NAME"] = rule.name
        processEnv["HOOK_EVENT"] = rule.event.rawValue
        processEnv["TOOL_NAME"] = toolName
        if let inputData = try? JSONSerialization.data(withJSONObject: input),
            let inputJSON = String(data: inputData, encoding: .utf8)
        {  // swiftlint:disable:this opening_brace
            processEnv["TOOL_INPUT"] = inputJSON
        }
        processEnv["TOOL_OUTPUT"] = output
        for (key, value) in env {
            processEnv[key] = value
        }
        process.environment = processEnv

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            // 使用 async continuation 替代 waitUntilExit()，避免阻塞 co-op 线程池
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
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Hook error: \(error.localizedDescription)"
        }
    }

    // MARK: - Summary

    /// 生成 Hook 摘要 (供 LLM / 调试使用)
    public func summary() -> String {
        let snapshot: [HookRule] = rules
        if snapshot.isEmpty { return "（无 Hook 规则）" }
        return snapshot.map { rule in
            let status: String = rule.enabled ? "✓" : "✗"
            let pattern: String = rule.toolPattern.isEmpty ? "所有工具" : rule.toolPattern
            return "[\(status)] \(rule.event.rawValue) — \(pattern): \(rule.name)"
        }.joined(separator: "\n")
    }

    private func save() {
        let data: Data
        do {
            data = try JSONEncoder().encode(rules)
        } catch {
            print("[HooksService] Failed to encode rules: \(error)")
            return
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[HooksService] Failed to save hooks.json: \(error)")
        }
    }
}
