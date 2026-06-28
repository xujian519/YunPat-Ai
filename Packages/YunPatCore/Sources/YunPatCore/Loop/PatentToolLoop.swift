import Foundation
import YunPatNetworking

// MARK: - LoopExit (6 种退出分类)

public enum LoopExit: Sendable, Equatable {
    /// 正常结束，带最终回复
    case finalResponse(String)
    /// 达到迭代上限（末轮工具仍执行）
    case iterationCapReached(String)
    /// 工具被用户拒绝
    case toolRejected(String)
    /// 被取消
    case cancelled
    /// complete/clarify 拦截结束
    case endedBySurface(EndedBySurface)
    /// 窗口放不下（压缩后仍超限）
    case overBudget(String)

    public var summary: String {
        switch self {
        case .finalResponse(let s): return s
        case .iterationCapReached(let s): return s
        case .toolRejected(let s): return s
        case .cancelled: return "cancelled"
        case .endedBySurface(let e): return e.summary
        case .overBudget(let s): return s
        }
    }
}

public struct EndedBySurface: Sendable, Equatable {
    public let kind: SurfaceKind
    public let summary: String
    public init(kind: SurfaceKind, summary: String) {
        self.kind = kind; self.summary = summary
    }
}

public enum SurfaceKind: String, Sendable, Equatable {
    case complete      // task_complete 拦截
    case clarify       // ask_user/clarify 拦截
}

// MARK: - PatentLoopPolicy（命名旋钮）

public struct PatentLoopPolicy: Sendable {
    public let maxIterations: Int
    public let stopOnToolRejection: Bool
    public let dedupeNoticeEnabled: Bool
    public let budgetWarningThreshold: Int

    public init(
        maxIterations: Int = 20,
        stopOnToolRejection: Bool = true,
        dedupeNoticeEnabled: Bool = true,
        budgetWarningThreshold: Int = 3
    ) {
        self.maxIterations = maxIterations
        self.stopOnToolRejection = stopOnToolRejection
        self.dedupeNoticeEnabled = dedupeNoticeEnabled
        self.budgetWarningThreshold = budgetWarningThreshold
    }

    /// Chat surface 默认 policy
    public static let chat = PatentLoopPolicy(
        stopOnToolRejection: true,
        dedupeNoticeEnabled: true
    )

    /// HTTP/Plugin surface 默认 policy
    public static let http = PatentLoopPolicy(
        stopOnToolRejection: false,
        dedupeNoticeEnabled: false
    )

    /// 专利五步流程 policy（更多迭代预算）
    public static let patentFlow = PatentLoopPolicy(
        maxIterations: 30,
        stopOnToolRejection: true,
        dedupeNoticeEnabled: true,
        budgetWarningThreshold: 5
    )
}

// MARK: - 流式模型输出分块

public enum ModelStepChunk: Sendable {
    case textDelta(String)       // 增量文本（流式）
    case toolCall(ToolCall)      // 完整工具调用
    case done(String)            // 流结束，final text
    case error(String)           // 错误
}

// MARK: - PatentLoopHooks（surface 提供的回调）

public struct PatentLoopHooks: Sendable {
    public typealias BuildMessages = @Sendable () async -> [Message]
    public typealias ModelStep = @Sendable ([Message], [ToolSpec]) async throws -> ModelStepResult
    public typealias ModelStream = @Sendable ([Message], [ToolSpec]) async throws -> AsyncThrowingStream<ModelStepChunk, Error>
    public typealias ExecuteTool = @Sendable (ToolCall) async -> ToolEnvelope
    public typealias ExecuteBatch = @Sendable ([ToolCall], ToolContext) async -> [ToolEnvelope]
    public typealias OnTodoUpdate = @Sendable (String) async -> Void
    public typealias OnClarify = @Sendable (ClarifyRequest) async -> String
    public typealias OnStreamChunk = @Sendable (String) async -> Void

    public let buildMessages: BuildMessages
    public let modelStep: ModelStep?
    public let modelStream: ModelStream?
    public let executeTool: ExecuteTool
    public let executeBatch: ExecuteBatch
    public let onTodoUpdate: OnTodoUpdate?
    public let onClarify: OnClarify?
    public let onStreamChunk: OnStreamChunk?

    public init(
        buildMessages: @escaping BuildMessages,
        modelStep: ModelStep? = nil,
        modelStream: ModelStream? = nil,
        executeTool: @escaping ExecuteTool,
        executeBatch: @escaping ExecuteBatch,
        onTodoUpdate: OnTodoUpdate? = nil,
        onClarify: OnClarify? = nil,
        onStreamChunk: OnStreamChunk? = nil
    ) {
        self.buildMessages = buildMessages
        self.modelStep = modelStep
        self.modelStream = modelStream
        self.executeTool = executeTool
        self.executeBatch = executeBatch
        self.onTodoUpdate = onTodoUpdate
        self.onClarify = onClarify
        self.onStreamChunk = onStreamChunk
    }
}

// MARK: - 模型调用结果

public enum ModelStepResult: Sendable {
    case textResponse(String)
    case toolCalls([ToolCall])
    case error(String)
}

public struct ToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let arguments: [String: String]

    public init(id: String, name: String, arguments: [String: String] = [:]) {
        self.id = id; self.name = name; self.arguments = arguments
    }

    public static func == (l: ToolCall, r: ToolCall) -> Bool {
        l.id == r.id && l.name == r.name
    }
}

public struct ToolSpec: Sendable {
    public let name: String
    public let description: String
    public let parameters: String
    public init(name: String, description: String, parameters: String = "{}") {
        self.name = name; self.description = description; self.parameters = parameters
    }
}

public struct ToolEnvelope: Sendable {
    public let toolName: String
    public let content: String
    public let kind: ToolResultKind
    public let entries: [Entry]?
    public let isError: Bool
    /// 结构化错误码（nil 表示非错误响应）
    public let errorCode: String?
    /// 可选的修复建议（如 "Set allow_private: true"）
    public let errorHint: String?
    /// 非致命警告列表
    public let warnings: [String]?
    public init(
        toolName: String, content: String, kind: ToolResultKind = .other,
        entries: [Entry]? = nil, isError: Bool = false,
        errorCode: String? = nil, errorHint: String? = nil,
        warnings: [String]? = nil
    ) {
        self.toolName = toolName; self.content = content
        self.kind = kind; self.entries = entries
        self.isError = isError
        self.errorCode = errorCode; self.errorHint = errorHint
        self.warnings = warnings
    }
}

// MARK: - ToolEnvelope + ToolResponse

extension ToolEnvelope {
    /// 从 ToolResponse 构造（新标准化路径）
    public init(from response: ToolResponse, toolName: String) {
        self.toolName = toolName
        self.content = response.jsonString()
        self.kind = response.ok ? .other : .error
        self.isError = !response.ok
        self.errorCode = response.error?.code
        self.errorHint = response.error?.hint
        self.warnings = response.warnings
        self.entries = nil
    }
}

public enum ToolResultKind: String, Sendable {
    case listing       // 目录/检索结果 → entries 含可复制 path
    case file           // 文件内容
    case notFound       // 路径/查询无结果
    case error          // 工具执行失败
    case other
}

public struct Entry: Sendable {
    public let path: String
    public let kind: EntryKind
    public let label: String?
    public init(path: String, kind: EntryKind = .file, label: String? = nil) {
        self.path = path; self.kind = kind; self.label = label
    }
}
public enum EntryKind: String, Sendable {
    case file
    case directory
    case patent
    case reference
}

// MARK: - ClarifyRequest

public struct ClarifyRequest: Sendable {
    public let question: String
    public let options: [String]
    public let allowMultiple: Bool
    public init(question: String, options: [String] = [], allowMultiple: Bool = false) {
        self.question = question; self.options = options; self.allowMultiple = allowMultiple
    }
}

// MARK: - PatentToolLoop（单一驱动）

/// 单一 Loop 驱动 — 所有 surface 共用
public actor PatentToolLoop {

    private var taskState: PatentHarnessTaskState = PatentHarnessTaskState()
    private var compactionWatermark: CompactionWatermark = CompactionWatermark()
    private var manifest: CapabilityManifest?
    private let batchExecutor: ToolBatchExecutor = .shared

    public init() {}

    /// 设置 session 初始化的 capability manifest
    public func setManifest(_ m: CapabilityManifest) {
        self.manifest = m
    }

    /// 运行一次 agent 循环
    public func run(
        request: UserRequest,
        policy: PatentLoopPolicy,
        hooks: PatentLoopHooks,
        provider: ModelProvider = .deepseek
    ) async -> LoopExit {
        var iteration = 0
        let interceptNames: Set<String> = ["complete", "task_complete", "clarify", "ask_user",
                                            "todo", "capabilities_discover", "capabilities_load"]

        taskState.beginMessage()
        let budget = ContextBudget(capabilities: provider.defaultCapabilities)

        while iteration < policy.maxIterations {
            iteration += 1

            // 1. Stage system notices
            var notices: [String] = []
            if iteration >= policy.maxIterations - policy.budgetWarningThreshold {
                let remaining = policy.maxIterations - iteration
                notices.append("[System Notice] Tool call budget: \(remaining) of \(policy.maxIterations) remaining.")
            }
            if policy.dedupeNoticeEnabled, let nudge = taskState.nudge {
                notices.append("[System Notice] \(nudge)")
            }

            // 2. Build messages + capability manifest + system notice
            var messages = await hooks.buildMessages()

            if iteration == 1, let manifestBlock = manifest?.renderedBlock, !manifestBlock.isEmpty {
                messages.insert(Message(role: .system, content: manifestBlock), at: 0)
            }

            for notice in notices {
                messages.append(Message(role: .system, content: notice))
            }

            // 3. Compact history if needed
            let compacted = compactionWatermark.compact(
                messages: messages, request: ChatRequest(model: "", messages: messages),
                budget: budget, provider: provider
            )
            if compacted.overBudget {
                return .overBudget("Context window exceeded even after compaction.")
            }
            if compacted.messages.count < messages.count {
                messages = compacted.messages
                if let note = compacted.note {
                    messages.append(Message(role: .system, content: note))
                }
            }

            // 4. Model step（优先流式 modelStream，回退 modelStep）
            let tools = registeredTools()

            if let modelStream = hooks.modelStream {
                do {
                    let stream = try await modelStream(messages, tools)
                    var fullText = ""
                    for try await chunk in stream {
                        switch chunk {
                        case .textDelta(let t):
                            fullText += t
                            await hooks.onStreamChunk?(t)
                        case .done(let text):
                            let final = fullText.isEmpty ? text : fullText
                            return .finalResponse(final.isEmpty ? text : final)
                        case .toolCall(let call):
                            // 工具调用走批处理
                            let ctx = ToolContext(toolId: call.id, projectFolder: "", selectedProvider: provider)
                            let (results, updatedState) = await batchExecutor.execute(
                                calls: [call], ctx: ctx,
                                stateSnapshot: taskState,
                                executor: hooks.executeTool,
                                permissionGate: { _ in true },
                                onIntercept: { [hooks] (tc: ToolCall, env: ToolEnvelope) async -> InterceptAction in
                                    if interceptNames.contains(tc.name), !env.isError {
                                        if tc.name == "todo" { await hooks.onTodoUpdate?(env.content); return .continue }
                                        if tc.name == "complete" || tc.name == "task_complete" {
                                            guard AgentLoopTools.validate(summary: env.content) else { return .continue }
                                            return .endRun
                                        }
                                        if tc.name == "clarify" || tc.name == "ask_user" { return .endRun }
                                    }
                                    return .continue
                                }
                            )
                            taskState = updatedState
                            for (i, c) in [call].enumerated() {
                                guard i < results.count, !results[i].isError else { continue }
                                if c.name == "complete" || c.name == "task_complete" {
                                    return .endedBySurface(EndedBySurface(kind: .complete, summary: results[i].content))
                                }
                                if c.name == "clarify" || c.name == "ask_user" {
                                    return .endedBySurface(EndedBySurface(kind: .clarify, summary: results[i].content))
                                }
                            }
                            if results.contains(where: { $0.isError }) && policy.stopOnToolRejection {
                                return .toolRejected("Tool rejected by user or system")
                            }
                        case .error(let e):
                            return .finalResponse("Error: \(e)")
                        }
                    }
                    return .finalResponse(fullText.isEmpty ? "No response" : fullText)
                } catch {
                    return .finalResponse("Error: \(error.localizedDescription)")
                }
            }

            let step: ModelStepResult
            do {
                guard let modelStep = hooks.modelStep else {
                    return .finalResponse("Error: No model step configured")
                }
                step = try await modelStep(messages, tools)
            } catch {
                return .finalResponse("Error: \(error.localizedDescription)")
            }

            switch step {
            case .textResponse(let text):
                return .finalResponse(text)

            case .toolCalls(let calls):
                // 5. Batch execute via ToolBatchExecutor
                let ctx = ToolContext(toolId: "", projectFolder: "", selectedProvider: provider)
                let (results, updatedState) = await batchExecutor.execute(
                    calls: calls, ctx: ctx,
                    stateSnapshot: taskState,
                    executor: hooks.executeTool,
                    permissionGate: { _ in true },
                    onIntercept: { [hooks] (call: ToolCall, env: ToolEnvelope) async -> InterceptAction in
                        if interceptNames.contains(call.name), !env.isError {
                            if call.name == "todo" {
                                await hooks.onTodoUpdate?(env.content)
                                return InterceptAction.continue
                            }
                            if call.name == "complete" || call.name == "task_complete" {
                                guard AgentLoopTools.validate(summary: env.content) else {
                                    return InterceptAction.continue
                                }
                                return InterceptAction.endRun
                            }
                            if call.name == "clarify" || call.name == "ask_user" {
                                return InterceptAction.endRun  // clarify → endedBySurface(clarify)
                            }
                        }
                        return InterceptAction.continue
                    }
                )
                taskState = updatedState

                // 6. Check intercept in results (simplified — executor already handled)
                for (i, call) in calls.enumerated() {
                    guard i < results.count, !results[i].isError else { continue }
                    if call.name == "complete" || call.name == "task_complete" {
                        return .endedBySurface(EndedBySurface(kind: .complete, summary: results[i].content))
                    }
                    if call.name == "clarify" || call.name == "ask_user" {
                        return .endedBySurface(EndedBySurface(kind: .clarify, summary: results[i].content))
                    }
                }

                // 7. Check for rejection
                let rejected = results.contains { $0.isError }
                if rejected && policy.stopOnToolRejection {
                    return .toolRejected("Tool rejected by user or system")
                }

            case .error(let e):
                return .finalResponse("Error: \(e)")
            }

            taskState.beginMessage()
        }

        return .iterationCapReached("Reached max iterations (\(policy.maxIterations))")
    }

    // MARK: - Helpers

    private func registeredTools() -> [ToolSpec] {
        ToolDispatch.shared.allToolSpecs
    }
}

/// complete/clarify 工具校验
public enum AgentLoopTools: Sendable {
    /// complete summary 校验 — 拒绝占位符，要求 ≥30 字实质描述
    public static func validate(summary: String) -> Bool {
        let placeholders: Set<String> = [
            "done", "ok", "完成", "已完成", "好了", "可以了",
            "looks good", "complete", "finished", "good", "yes",
        ]
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 30 { return false }
        if placeholders.contains(trimmed.lowercased()) { return false }
        return true
    }
}

// MARK: - Harness Task State (结构化去重 + reactive nudge + canonical invalidation)

public struct PatentHarnessTaskState: Sendable {
    /// within-message 调用缓存：canonicalCall → 结果文本（重放用）
    private var freshResults: [String: String] = [:]
    /// 写操作 invalidate 路径集
    private var invalidatedPaths: Set<String> = []
    public private(set) var nudge: String? = nil
    private var consecutiveListings = 0
    /// 文件根路径（用于 canonicalPath 解析）
    private var rootPath: String = ""

    public mutating func beginMessage() {
        freshResults.removeAll()
        nudge = nil
    }

    /// 规范路径（消除 .. 和 .）
    public static func canonicalPath(_ path: String, relativeTo root: String = "") -> String {
        let base = root.isEmpty ? FileManager.default.currentDirectoryPath : root
        let absolute: String
        if path.hasPrefix("/") { absolute = path }
        else { absolute = (base as NSString).appendingPathComponent(path) }
        // 消除 .. 和 .
        let nsPath = absolute as NSString
        let standardized = nsPath.standardizingPath
        return standardized
    }

    /// 记录工具调用结果，含去重和 reactive nudge
    public mutating func record(call: ToolCall, envelope: ToolEnvelope) {
        let key = canonicalKey(call: call)
        freshResults[key] = envelope.content

        // 写工具 invalidate 对应路径
        if envelope.toolName == "write_file" || envelope.toolName == "file_write"
            || envelope.toolName == "edit_file" || envelope.toolName == "file_edit" {
            if let path = call.arguments["path"] {
                let canon = Self.canonicalPath(path)
                invalidatedPaths.insert(canon)
                // 清除该 path 的 fresh read
                for k in freshResults.keys where k.contains(canon) {
                    freshResults.removeValue(forKey: k)
                }
            }
        }

        // reactive nudge：连续 listing 无中间 read
        let listingTools: Set<String> = ["file_read", "list_files", "search_files",
                                          "patent_search", "legal_status_query", "knowledge_search"]
        if listingTools.contains(envelope.toolName) {
            consecutiveListings += 1
            if consecutiveListings >= 2 {
                nudge = "You've searched/listed twice without reading a specific result. Copy an entry's path and read it."
            }
        } else if envelope.toolName == "read_file" && !envelope.isError {
            consecutiveListings = 0
            nudge = nil
        }
    }

    /// 检查是否应去重（within-message）：调用已存在且路径未被 invalidate
    public func deduplicate(call: ToolCall) -> Bool {
        let key = canonicalKey(call: call)
        guard freshResults.keys.contains(key) else { return false }
        // 检查路径是否被 invalidate
        if let path = call.arguments["path"] {
            let canon = Self.canonicalPath(path)
            if invalidatedPaths.contains(canon) { return false }
        }
        return true
    }

    /// 获取去重时应重放的结果
    public func replay(for call: ToolCall) -> String? {
        let key = canonicalKey(call: call)
        return freshResults[key]
    }

    /// 重置（跨 session）
    public mutating func reset() {
        freshResults.removeAll()
        invalidatedPaths.removeAll()
        consecutiveListings = 0
        nudge = nil
    }

    private func canonicalKey(call: ToolCall) -> String {
        "\(call.name):\(hash(args: call.arguments))"
    }

    private func hash(args: [String: String]) -> String {
        let sorted = args.keys.sorted().map { "\($0)=\(args[$0] ?? "")" }.joined(separator: "&")
        return String(sorted.hashValue)
    }
}
