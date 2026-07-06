import Foundation
import os

// MARK: - Hook 事件类型

public enum HookEvent: String, CaseIterable, Codable, Sendable {
    case preToolUse
    case postToolUse
    case preModelCall
    case postModelCall
    case sessionStart
    case sessionEnd
    case taskStart
    case taskComplete
    case buildFailure
}

public enum HookDecision: String, Sendable {
    case allow
    case block
}

public enum HookError: Error, Sendable {
    case exitCode(Int32)
}

// MARK: - Hook Rule

public struct HookRule: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var event: HookEvent

    /// 工具名称匹配模式 (空 = 匹配所有)。支持 `*` 通配符前缀匹配。
    public var toolPattern: String

    /// 执行器类型: shell / http / agent
    public var executorType: HookExecutorType

    /// 命令/URL/Agent 指令
    public var command: String

    public var enabled: Bool

    public init(
        name: String,
        event: HookEvent,
        toolPattern: String = "",
        executorType: HookExecutorType = .shell,
        command: String,
        enabled: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.event = event
        self.toolPattern = toolPattern
        self.executorType = executorType
        self.command = command
        self.enabled = enabled
    }

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

public struct ToolInput: @unchecked Sendable {
    public let raw: [String: Any]
    public init(_ raw: [String: Any]) { self.raw = raw }
}

// MARK: - Hooks Service

public actor HooksService {
    public static let shared: HooksService = HooksService()
    private let logger = Logger(subsystem: "com.yunpat", category: "HooksService")
    private(set) var rules: [HookRule] = []
    private let fileURL: URL

    // 执行器注册表
    private var shellExecutor: ShellHookExecutor = ShellHookExecutor()
    private var httpExecutor: HTTPHookExecutor = HTTPHookExecutor()
    private var agentExecutor: AgentHookExecutor?

    private init() {
        let home: URL = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Documents/YunPat")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("hooks.json")
        if let data = try? Data(contentsOf: fileURL) {
            do {
                self.rules = try JSONDecoder().decode([HookRule].self, from: data)
            } catch {
                logger.error("Failed to decode hooks.json: \(error, privacy: .public)")
            }
        }
    }

    // MARK: - 执行器配置

    public func setAgentExecutor(_ executor: AgentHookExecutor) {
        agentExecutor = executor
    }

    // MARK: - CRUD

    public func add(_ rule: HookRule) {
        rules.append(rule)
        save()
    }

    public func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    public func update(_ rule: HookRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
            save()
        }
    }

    public func toggle(id: UUID) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].enabled.toggle()
            save()
        }
    }

    // MARK: - Pre/Post Tool Hooks

    public func runPreToolHooks(
        toolName: String,
        input: ToolInput
    ) async -> (decision: HookDecision, message: String?) {
        for rule in filteredRules(event: .preToolUse, toolName: toolName) {
            let result: HookExecResult = await executeHook(rule, toolName: toolName, input: input.raw)
            if !result.accepted {
                return (.block, result.output.isEmpty ? "Blocked by hook '\(rule.name)'" : result.output)
            }
        }
        return (.allow, nil)
    }

    public func runPostToolHooks(toolName: String, input: ToolInput, output: String) async -> String? {
        var transformed: String = output
        var changed: Bool = false
        for rule in filteredRules(event: .postToolUse, toolName: toolName) {
            let result: HookExecResult = await executeHook(rule, toolName: toolName, input: input.raw, output: output)
            let trimmed: String = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                transformed = trimmed
                changed = true
            }
        }
        return changed ? transformed : nil
    }

    // MARK: - 事件 Hooks

    public func runEventHooks(_ event: HookEvent, toolName: String = "", context: [String: String] = [:]) async {
        for rule in rules where rule.event == event && rule.enabled && rule.toolPattern.isEmpty {
            _ = await executeHook(rule, toolName: toolName, input: [:], output: "", env: context)
        }
    }

    // MARK: - 模型调用 Hooks

    public func runPreModelHooks(toolName: String = "") async -> Bool {
        for rule in filteredRules(event: .preModelCall, toolName: toolName) {
            let result: HookExecResult = await executeHook(rule, toolName: toolName, input: [:])
            if !result.accepted { return false }
        }
        return true
    }

    public func runPostModelHooks(toolName: String = "", output: String = "") async {
        for rule in filteredRules(event: .postModelCall, toolName: toolName) {
            _ = await executeHook(rule, toolName: toolName, input: [:], output: output)
        }
    }

    // MARK: - Session Hooks

    public func runSessionStartHooks() async {
        for rule in rules where rule.event == .sessionStart && rule.enabled && rule.toolPattern.isEmpty {
            _ = await executeHook(rule, toolName: "", input: [:])
        }
    }

    public func runSessionEndHooks(summary: String = "") async {
        for rule in rules where rule.event == .sessionEnd && rule.enabled && rule.toolPattern.isEmpty {
            _ = await executeHook(rule, toolName: "", input: [:], output: summary)
        }
    }

    // MARK: - 执行

    private func executeHook(
        _ rule: HookRule,
        toolName: String,
        input: [String: Any],
        output: String = "",
        env: [String: String] = [:]
    ) async -> HookExecResult {
        let executor: HookExecuting = {
            switch rule.executorType {
            case .shell: return shellExecutor
            case .http: return httpExecutor
            case .agent:
                guard let agent = agentExecutor else {
                    return ErrorHookExecutor(message: "Agent executor not configured — cannot execute agent hook")
                }
                return agent
            }
        }()
        let inputJSON: String = {
            guard let data = try? JSONSerialization.data(withJSONObject: input),
                  let str = String(data: data, encoding: .utf8)
            else { return "{}" }
            return str
        }()
        return await executor.execute(
            command: rule.command,
            toolName: toolName,
            inputJSON: inputJSON,
            output: output,
            env: env
        )
    }

    // MARK: - Summary

    public func summary() -> String {
        if rules.isEmpty { return "（无 Hook 规则）" }
        return rules.map { rule in
            let status: String = rule.enabled ? "✓" : "✗"
            let pattern: String = rule.toolPattern.isEmpty ? "所有工具" : rule.toolPattern
            let type: String = rule.executorType.rawValue
            return "[\(status)] \(rule.event.rawValue) — \(pattern) (\(type)): \(rule.name)"
        }.joined(separator: "\n")
    }

    // MARK: - Internal

    private func filteredRules(event: HookEvent, toolName: String) -> [HookRule] {
        rules.filter { $0.event == event && $0.enabled && $0.matches(toolName: toolName) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
