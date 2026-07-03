// swiftlint:disable file_length
import Foundation
import YunPatNetworking

// MARK: - LoopExit (6 种退出分类)

/// 循环退出类型 — 6 种退出分类
///
/// 每次 `PatentToolLoop.run()` 返回一种退出类型，包含执行摘要。
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

    /// 获取退出的文本摘要
    public var summary: String {
        switch self {
        case .finalResponse(let text): return text
        case .iterationCapReached(let text): return text
        case .toolRejected(let text): return text
        case .cancelled: return "cancelled"
        case .endedBySurface(let surface): return surface.summary
        case .overBudget(let text): return text
        }
    }
}

/// 由 surface 拦截结束循环的详细信息
public struct EndedBySurface: Sendable, Equatable {
    /// 结束类型（complete / clarify）
    public let kind: SurfaceKind
    /// 结束摘要
    public let summary: String
    public init(kind: SurfaceKind, summary: String) {
        self.kind = kind
        self.summary = summary
    }
}

/// Surface 拦截结束类型
public enum SurfaceKind: String, Sendable, Equatable {
    /// task_complete 拦截
    case complete
    /// ask_user/clarify 拦截
    case clarify
}

// MARK: - PatentLoopPolicy（命名旋钮）

/// 循环策略 — 控制最大迭代次数、工具拒绝行为、预算警告等
///
/// 提供三种预设：`.chat`（对话）、`.http`（无交互）、`.patentFlow`（专利分析）
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
    public static let chat: PatentLoopPolicy = PatentLoopPolicy(
        stopOnToolRejection: true,
        dedupeNoticeEnabled: true
    )

    /// HTTP/Plugin surface 默认 policy
    public static let http: PatentLoopPolicy = PatentLoopPolicy(
        stopOnToolRejection: false,
        dedupeNoticeEnabled: false
    )

    /// 专利五步流程 policy（更多迭代预算）
    public static let patentFlow: PatentLoopPolicy = PatentLoopPolicy(
        maxIterations: 30,
        stopOnToolRejection: true,
        dedupeNoticeEnabled: true,
        budgetWarningThreshold: 5
    )
}

// MARK: - 流式模型输出分块

/// 流式模型输出分块 — 供 PatentLoopHooks.modelStream 使用
public enum ModelStepChunk: Sendable {
    case textDelta(String)  // 增量文本（流式）
    case toolCall(ToolCall)  // 完整工具调用
    case done(String)  // 流结束，final text
    case error(String)  // 错误
}

// MARK: - PatentLoopHooks（surface 提供的回调）

/// Surface 提供的回调集合 — 桥接 PatentToolLoop 与外部 surface（Chat/HTTP/Plugin）
///
/// 每个 surface 提供 buildMessages、modelStream/modelStep、executeTool 等回调，
/// PatentToolLoop 通过此 hooks 驱动模型调用与工具执行。
public struct PatentLoopHooks: Sendable {
    public typealias BuildMessages = @Sendable () async -> [Message]
    public typealias ModelStep = @Sendable ([Message], [ToolSpec]) async throws -> ModelStepResult
    public typealias ModelStream =
        @Sendable ([Message], [ToolSpec]) async throws
        -> AsyncThrowingStream<ModelStepChunk, Error>
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

/// 模型调用结果 — PatentLoopHooks.modelStep 的返回类型
public enum ModelStepResult: Sendable {
    case textResponse(String)
    case toolCalls([ToolCall])
    case error(String)
}

/// LLM 发起的工具调用请求
public struct ToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let arguments: [String: String]

    public init(id: String, name: String, arguments: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    public static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}

/// 工具规范描述 — 供 LLM function calling 使用
public struct ToolSpec: Sendable {
    public let name: String
    public let description: String
    public let parameters: String
    public init(name: String, description: String, parameters: String = "{}") {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// 工具执行结果信封 — 包含结果内容、类型、错误信息等
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
        self.toolName = toolName
        self.content = content
        self.kind = kind
        self.entries = entries
        self.isError = isError
        self.errorCode = errorCode
        self.errorHint = errorHint
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

/// 工具结果类型分类
public enum ToolResultKind: String, Sendable {
    case listing  // 目录/检索结果 → entries 含可复制 path
    case file  // 文件内容
    case notFound  // 路径/查询无结果
    case error  // 工具执行失败
    case other
}

/// 可复制的路径条目 — 用于检索/目录结果
public struct Entry: Sendable {
    public let path: String
    public let kind: EntryKind
    public let label: String?
    public init(path: String, kind: EntryKind = .file, label: String? = nil) {
        self.path = path
        self.kind = kind
        self.label = label
    }
}
/// 条目类型
public enum EntryKind: String, Sendable {
    case file
    case directory
    case patent
    case reference
}

// MARK: - ClarifyRequest

/// 澄清请求 — 当 LLM 需要用户补充信息时使用
public struct ClarifyRequest: Sendable {
    public let question: String
    public let options: [String]
    public let allowMultiple: Bool
    public init(question: String, options: [String] = [], allowMultiple: Bool = false) {
        self.question = question
        self.options = options
        self.allowMultiple = allowMultiple
    }
}

// MARK: - PatentToolLoop（单一驱动）

/// 单一 Agent 循环驱动 — 所有 surface（Chat/HTTP/Plugin）共用
///
/// 职责：
/// - 构建消息序列（含 manifest、system notice）
/// - 消息压缩（CompactionWatermark）
/// - 模型调用（流式或整段）
/// - 工具批处理（ToolBatchExecutor）
/// - 拦截 complete/clarify 等循环控制工具
public actor PatentToolLoop {

    private var taskState: PatentHarnessTaskState = PatentHarnessTaskState()
    private var compactionWatermark: CompactionWatermark = CompactionWatermark()
    private var manifest: CapabilityManifest?
    private let batchExecutor: ToolBatchExecutor = .shared
    private var stuckGuard: StuckGuard = StuckGuard()
    private var loopGuard: LoopGuard = LoopGuard()
    private var consecutiveReads: Int = 0

    public init() {}

    /// 设置 session 的 Capability manifest（首次迭代注入到 system message）
    public func setManifest(_ manifest: CapabilityManifest) {
        self.manifest = manifest
    }

    // 运行一次 agent 循环
    //
    // 循环体：构建消息 → 压缩 → 模型调用 → 工具批处理 → 检查退出条件 → 下一轮
    // - Parameters:
    //   - request: 用户请求
    //   - policy: 循环策略（最大迭代次数、工具拒绝行为等）
    //   - hooks: surface 回调集合
    //   - provider: 模型提供商
    // - Returns: 循环退出类型和摘要
    // swiftlint:disable:next function_body_length
    public func run(
        request: UserRequest,
        policy: PatentLoopPolicy,
        hooks: PatentLoopHooks,
        provider: ModelProvider = .deepseek
    ) async -> LoopExit {
        var iteration: Int = 0
        let interceptNames: Set<String> = [
            "complete", "task_complete", "clarify", "ask_user",
            "todo", "capabilities_discover", "capabilities_load"
        ]

        taskState.beginMessage()
        let budget: ContextBudget = ContextBudget(capabilities: provider.defaultCapabilities)

        while iteration < policy.maxIterations {
            iteration += 1

            // 1. Stage system notices
            var notices: [String] = []
            if let iterNudge = loopGuard.checkIteration(iteration) {
                notices.append(iterNudge)
            }
            if let readNudge = loopGuard.checkConsecutiveReads(consecutiveReads) {
                notices.append(readNudge)
            }
            if iteration >= policy.maxIterations - policy.budgetWarningThreshold {
                let remaining: Int = policy.maxIterations - iteration
                notices.append("[System Notice] Tool call budget: \(remaining) of \(policy.maxIterations) remaining.")
            }
            if policy.dedupeNoticeEnabled, let nudge = taskState.nudge {
                notices.append("[System Notice] \(nudge)")
            }

            // 2. Build messages + capability manifest + system notice
            var messages: [Message] = await hooks.buildMessages()

            if iteration == 1, let manifestBlock = manifest?.renderedBlock, !manifestBlock.isEmpty {
                messages.insert(Message(role: .system, content: manifestBlock), at: 0)
            }

            for notice in notices {
                messages.append(Message(role: .system, content: notice))
            }

            // 3. Compact history if needed
            let compacted: CompactResult = compactionWatermark.compact(
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
            let tools: [ToolSpec] = registeredTools()

            if let modelStream = hooks.modelStream {
                do {
                    let stream: AsyncThrowingStream<ModelStepChunk, Error> = try await modelStream(messages, tools)
                    var fullText: String = ""
                    for try await chunk in stream {
                        switch chunk {
                        case .textDelta(let text):
                            fullText += text
                            await hooks.onStreamChunk?(text)
                        case .done(let text):
                            let finalText: String = fullText.isEmpty ? text : fullText
                            return .finalResponse(finalText.isEmpty ? text : finalText)
                        case .toolCall(let call):
                            // 工具调用走批处理
                            let ctx: ToolContext = ToolContext(
                                toolId: call.id, projectFolder: "",
                                selectedProvider: provider
                            )
                            let (results, updatedState): ([ToolEnvelope], PatentHarnessTaskState) =
                                await batchExecutor.execute(
                                    calls: [call], ctx: ctx,
                                    stateSnapshot: taskState,
                                    executor: hooks.executeTool,
                                    permissionGate: { _ in true },
                                    preExecutionGate: { _ in .allow },
                                    onIntercept: {
                                        [hooks] (call: ToolCall, env: ToolEnvelope) async -> InterceptAction in
                                        if interceptNames.contains(call.name), !env.isError {
                                            if call.name == "todo" {
                                                await hooks.onTodoUpdate?(env.content)
                                                return .continue
                                            }
                                            if call.name == "complete" || call.name == "task_complete" {
                                                guard AgentLoopTools.validate(summary: env.content)
                                                else { return .continue }
                                                return .endRun
                                            }
                                            if call.name == "clarify" || call.name == "ask_user" { return .endRun }
                                        }
                                        return .continue
                                    }
                                )
                            taskState = updatedState
                            for (index, callItem) in [call].enumerated() {
                                guard index < results.count, !results[index].isError else { continue }
                                if callItem.name == "complete" || callItem.name == "task_complete" {
                                    return .endedBySurface(
                                        EndedBySurface(kind: .complete, summary: results[index].content)
                                    )
                                }
                                if callItem.name == "clarify" || callItem.name == "ask_user" {
                                    return .endedBySurface(
                                        EndedBySurface(kind: .clarify, summary: results[index].content)
                                    )
                                }
                            }
                            if results.contains(where: { $0.isError }) && policy.stopOnToolRejection {
                                return .toolRejected("Tool rejected by user or system")
                            }
                        case .error(let error):
                            return .finalResponse("Error: \(error)")
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
                let ctx: ToolContext = ToolContext(toolId: "", projectFolder: "", selectedProvider: provider)
                let (results, updatedState): ([ToolEnvelope], PatentHarnessTaskState) = await batchExecutor.execute(
                    calls: calls, ctx: ctx,
                    stateSnapshot: taskState,
                    executor: hooks.executeTool,
                    permissionGate: { _ in true },
                    preExecutionGate: { _ in .allow },
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
                for (index, call) in calls.enumerated() {
                    guard index < results.count, !results[index].isError else { continue }
                    if call.name == "complete" || call.name == "task_complete" {
                        return .endedBySurface(EndedBySurface(kind: .complete, summary: results[index].content))
                    }
                    if call.name == "clarify" || call.name == "ask_user" {
                        return .endedBySurface(EndedBySurface(kind: .clarify, summary: results[index].content))
                    }
                }

                // 7. StuckGuard — 检测连续编辑失败
                for (index, call) in calls.enumerated() where index < results.count {
                    guard let nudge = stuckGuard.check(
                        toolName: call.name,
                        filePath: extractFilePath(from: call),
                        result: results[index].content
                    ) else { continue }
                    messages.append(Message(role: .system, content: nudge.message))
                    if nudge.resetAfter { stuckGuard.reset(filePath: nudge.path) }
                }

                // 8. Track consecutive reads
                let hasWrite = calls.contains { !loopGuard_readTools.contains($0.name) }
                if hasWrite { consecutiveReads = 0 } else { consecutiveReads += calls.count }

                // 9. Check for rejection
                let rejected: Bool = results.contains { $0.isError }
                if rejected && policy.stopOnToolRejection {
                    return .toolRejected("Tool rejected by user or system")
                }

            case .error(let error):
                return .finalResponse("Error: \(error)")
            }

            taskState.beginMessage()
        }

        return .iterationCapReached("Reached max iterations (\(policy.maxIterations))")
    }

    // MARK: - Helpers

    private func registeredTools() -> [ToolSpec] {
        ToolDispatch.shared.allToolSpecs
    }

    private func extractFilePath(from call: ToolCall) -> String? {
        call.arguments["file_path"] ?? call.arguments["path"]
    }
}

private let loopGuard_readTools: Set<String> = [
    "read_file", "list_files", "search_files",
    "knowledge_search", "patent_search"
]

/// complete/clarify 工具校验 — 拒绝占位符，要求实质性描述
public enum AgentLoopTools: Sendable {
    /// complete summary 校验 — 拒绝占位符，要求 ≥30 字实质描述
    public static func validate(summary: String) -> Bool {
        let placeholders: Set<String> = [
            "done", "ok", "完成", "已完成", "好了", "可以了",
            "looks good", "complete", "finished", "good", "yes"
        ]
        let trimmed: String = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 30 { return false }
        if placeholders.contains(trimmed.lowercased()) { return false }
        return true
    }
}

// MARK: - Harness Task State (结构化去重 + reactive nudge + canonical invalidation)

/// 任务执行状态 — 同一消息内调用去重、写操作 invalidate、连续 listing 黏性提醒
public struct PatentHarnessTaskState: Sendable {
    /// within-message 调用缓存：canonicalCall → 结果文本（重放用）
    private var freshResults: [String: String] = [:]
    /// 写操作 invalidate 路径集
    private var invalidatedPaths: Set<String> = []
    public private(set) var nudge: String?
    private var consecutiveListings: Int = 0
    /// 文件根路径（用于 canonicalPath 解析）
    private var rootPath: String = ""

    public mutating func beginMessage() {
        freshResults.removeAll()
        nudge = nil
    }

    /// 规范路径（消除 .. 和 .）
    public static func canonicalPath(_ path: String, relativeTo root: String = "") -> String {
        let base: String = root.isEmpty ? FileManager.default.currentDirectoryPath : root
        let absolute: String
        if path.hasPrefix("/") {
            absolute = path
        } else {
            absolute = (base as NSString).appendingPathComponent(path)
        }
        // 消除 .. 和 .
        let nsPath: NSString = absolute as NSString
        let standardized: String = nsPath.standardizingPath
        return standardized
    }

    /// 记录工具调用结果，含去重和 reactive nudge
    public mutating func record(call: ToolCall, envelope: ToolEnvelope) {
        let key: String = canonicalKey(call: call)
        freshResults[key] = envelope.content

        // 写工具 invalidate 对应路径
        if envelope.toolName == "write_file" || envelope.toolName == "file_write"
            || envelope.toolName == "edit_file" || envelope.toolName == "file_edit" {
            if let path = call.arguments["path"] {
                let canon: String = Self.canonicalPath(path)
                invalidatedPaths.insert(canon)
                // 清除该 path 的 fresh read
                for key in freshResults.keys where key.contains(canon) {
                    freshResults.removeValue(forKey: key)
                }
            }
        }

        // reactive nudge：连续 listing 无中间 read
        let listingTools: Set<String> = [
            "file_read", "list_files", "search_files",
            "patent_search", "legal_status_query", "knowledge_search"
        ]
        if listingTools.contains(envelope.toolName) {
            consecutiveListings += 1
            if consecutiveListings >= 2 {
                nudge =
                    "You've searched/listed twice without reading a specific result."
                    + " Copy an entry's path and read it."
            }
        } else if envelope.toolName == "read_file" && !envelope.isError {
            consecutiveListings = 0
            nudge = nil
        }
    }

    /// 检查是否应去重（within-message）：调用已存在且路径未被 invalidate
    public func deduplicate(call: ToolCall) -> Bool {
        let key: String = canonicalKey(call: call)
        guard freshResults.keys.contains(key) else { return false }
        // 检查路径是否被 invalidate
        if let path = call.arguments["path"] {
            let canon: String = Self.canonicalPath(path)
            if invalidatedPaths.contains(canon) { return false }
        }
        return true
    }

    /// 获取去重时应重放的结果
    public func replay(for call: ToolCall) -> String? {
        let key: String = canonicalKey(call: call)
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
        let sorted: String = args.keys.sorted().map { "\($0)=\(args[$0] ?? "")" }.joined(separator: "&")
        return String(sorted.hashValue)
    }
}
