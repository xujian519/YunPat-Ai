import Foundation
import YunPatNetworking

// MARK: - Sub-Agent Spawning Engine

/// 子代理扇出引擎
///
/// 设计参考 Agent-main (macOS26/Agent) 的 SubAgent:
/// - 独立消息历史的 TaskGroup 并行执行
/// - mailbox IPC 跨代理消息传递
/// - XML notification 完成通知
/// - 递归防传播: 子代理默认不含 spawn_sub_agent 工具
/// - 并发上限由 RuntimeConfig.maxSubAgents 控制
///
/// 对标 Tokio `util/wake_list.rs`：完成时通过 `AsyncStream` 批量通知，
/// 消除 `waitAll` 的 200ms 轮询延迟。
///
/// 专利场景适配:
/// - 三路并行分析: 新颖性 / 创造性 / 侵权判定
/// - 父代理汇总子代理的 XML notification 输出
public actor SubAgentEngine {
    public static let shared: SubAgentEngine = SubAgentEngine()
    /// 最大并发子代理数（可通过 `configure(config:)` 由 RuntimeConfig 覆盖）
    public var maxConcurrent: Int = 3

    /// 活跃子代理
    private var agents: [SubAgent] = []

    /// 对标 Tokio WakeList 的通知流
    private var notificationContinuations: [UUID: AsyncStream<String>.Continuation] = [:]

    private init() {}

    // MARK: - Configuration

    // MARK: - Spawning

    /// 已完成的代理数
    public var completedCount: Int {
        agents.filter { $0.status == .completed || $0.status == .failed }.count
    }

    /// 活跃代理数
    public var activeCount: Int {
        agents.filter { $0.status == .running }.count
    }

    /// 生成一个子代理，返回 spawn 确认文本。结果通过 notification XML 异步返回。
    @discardableResult
    public func spawn(
        name: String,
        prompt: String,
        projectFolder: String = "",
        maxIterations: Int = 10,
        toolGroupIDs: Set<String>? = nil,
        modelRouter: ModelRouter,
        provider: ModelProvider
    ) async -> String {
        guard activeCount < maxConcurrent else {
            return "Error: 已达最大并发 \(maxConcurrent) 个子代理。等待某个完成后重试。"
        }

        let agent = SubAgent(name: name, prompt: prompt, projectFolder: projectFolder)
        agent.maxIterations = maxIterations
        agent.toolGroupIDs = toolGroupIDs
        agents.append(agent)

        // 异步启动执行 — 完成后自动通知所有 waitAll 注册者
        agent.task = Task { [weak self] in
            guard let self else { return "Error: engine deallocated" }
            let notification: String = await execute(agent, router: modelRouter, provider: provider)
            await notifyAll(notification)
            return notification
        }

        return "子代理 '\(name)' 已启动 (id: \(agent.shortId))。完成后将收到 <task-notification> 通知。"
    }

    /// 批量生成子代理 (用于并行专利分析)
    public func spawnBatch(
        tasks: [(name: String, prompt: String)],
        projectFolder: String = "",
        modelRouter: ModelRouter,
        provider: ModelProvider
    ) async -> [String] {
        var results: [String] = []
        for (idx, task) in tasks.enumerated() {
            guard idx < maxConcurrent else {
                results.append("Skipped '\(task.name)': 已达并发上限")
                continue
            }
            let msg = await spawn(
                name: task.name,
                prompt: task.prompt,
                projectFolder: projectFolder,
                modelRouter: modelRouter,
                provider: provider
            )
            results.append(msg)
        }
        return results
    }

    /// 对标 Tokio WakeList：基于通知流等待所有子代理完成，消除 200ms 轮询
    ///
    /// - Parameter timeout: 超时秒数，默认 120
    /// - Returns: 所有非运行态子代理
    public func waitAll(timeout: TimeInterval = 120) async -> [SubAgent] {
        guard activeCount > 0 else { return agents.filter { $0.status != .running } }

        let stream = notificationStream()
        let start: Date = Date()
        for await _ in stream {
            if activeCount == 0 { break }
            if Date().timeIntervalSince(start) > timeout { break }
        }

        return agents.filter { $0.status != .running }
    }

    /// 注册通知流（对标 Tokio WakeList::push）
    ///
    /// 每次有子代理完成/失败时，该流会 yield 通知 XML
    public func notificationStream() -> AsyncStream<String> {
        let streamId: UUID = UUID()
        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.removeContinuation(streamId) }
            }
            Task { [weak self] in await self?.registerContinuation(streamId, continuation) }
        }
    }

    private func registerContinuation(_ id: UUID, _ continuation: AsyncStream<String>.Continuation) {
        notificationContinuations[id] = continuation
    }

    private func removeContinuation(_ id: UUID) {
        notificationContinuations.removeValue(forKey: id)
    }

    /// 对标 Tokio WakeList::wake_all：批量通知所有注册者，并在所有代理完成后清理
    private func notifyAll(_ notification: String) {
        for (_, continuation) in notificationContinuations {
            continuation.yield(notification)
        }
        // 所有子代理完成时，主动 finish 清除所有延续，防止悬挂泄漏
        // onTermination 中的 Task 会异步 remove，此处同步清空字典避免竞态
        if activeCount == 0 {
            for (_, continuation) in notificationContinuations {
                continuation.finish()
            }
            notificationContinuations.removeAll()
        }
    }

    /// 收集所有完成通知的 XML
    public func collectNotifications() -> [String] {
        agents.filter { $0.status == .completed || $0.status == .failed }
            .map { $0.notification }
    }

    /// 向指定名称的子代理发送消息 (mailbox IPC)
    public func sendMessage(to name: String, message: String) -> String {
        if let agent = agents.first(where: { $0.name == name && $0.status == .running }) {
            agent.appendMailbox(message)
            return "消息已投递到 '\(agent.name)'。"
        }
        // 尝试 ID 前缀匹配
        if let agent = agents.first(where: { $0.id.uuidString.hasPrefix(name) && $0.status == .running }) {
            agent.appendMailbox(message)
            return "消息已投递到 '\(agent.name)'。"
        }
        let activeNames = agents.filter { $0.status == .running }.map(\.name).joined(separator: ", ")
        return "Error: 未找到名为 '\(name)' 的运行中子代理。活跃代理: \(activeNames)"
    }

    /// 重置 (清理所有代理及通知流)
    public func reset() {
        for agent in agents {
            agent.task?.cancel()
        }
        agents.removeAll()
        // 清理所有通知流注册者
        for (_, continuation) in notificationContinuations {
            continuation.finish()
        }
        notificationContinuations.removeAll()
    }

    // MARK: - Execution

    // 执行子代理任务 (改用 PatentToolLoop 驱动)
    // swiftlint:disable:next function_body_length
    private func execute(_ agent: SubAgent, router: ModelRouter, provider: ModelProvider) async -> String {
        let loop: PatentToolLoop = PatentToolLoop()
        let request: UserRequest = UserRequest(content: agent.prompt)
        let hooks: PatentLoopHooks = PatentLoopHooks(
            buildMessages: { [prompt = agent.prompt, mailbox = agent.mailbox] in
                var msgs: [YunPatNetworking.Message] = [
                    .init(role: .user, content: prompt)
                ]
                if !mailbox.isEmpty {
                    msgs.append(
                        .init(
                            role: .user,
                            content: "<message from coordinator>\n\(mailbox.joined(separator: "\n"))\n</message>"))
                }
                return msgs
            },
            modelStep: { [router, provider] messages, _ in
                do {
                    let chatReq = ChatRequest(model: "deepseek-chat", messages: messages)
                    let stream = try await router.chat(chatReq, provider: provider)
                    var full: String = ""
                    for try await chunk in stream {
                        switch chunk {
                        case .text(let text): full += text
                        case .finish: break
                        case .error(let err): return .error(err.localizedDescription)
                        default: break
                        }
                    }
                    if full.contains("task_complete") || full.contains("complete") {
                        return .textResponse(full)
                    }
                    return .textResponse(full)
                } catch {
                    return .error(error.localizedDescription)
                }
            },
            executeTool: { [provider] call in
                let ctx = ToolContext(toolId: call.id, projectFolder: agent.projectFolder, selectedProvider: provider)
                return await ToolDispatch.executeCall(call, ctx: ctx)
            },
            executeBatch: { [provider] calls, ctx in
                var results: [ToolEnvelope] = []
                for call in calls {
                    let toolCtx = ToolContext(
                        toolId: call.id, projectFolder: ctx.projectFolder, selectedProvider: provider)
                    results.append(await ToolDispatch.executeCall(call, ctx: toolCtx))
                }
                return results
            }
        )

        let exit = await loop.run(
            request: request,
            policy: PatentLoopPolicy(maxIterations: agent.maxIterations),
            hooks: hooks
        )

        switch exit {
        case .endedBySurface, .finalResponse:
            agent.status = .completed
        default:
            agent.status = .failed
        }
        agent.result = exit.summary
        return agent.notification
    }
}

public final class SubAgent: Identifiable, @unchecked Sendable {
    public let id: UUID = UUID()
    public let name: String
    public let prompt: String
    public let projectFolder: String
    public let startTime: Date = Date()
    private let lock: NSLock = NSLock()
    private var _status: Status = .running
    private var _result: String = ""
    private var _mailbox: [String] = []
    public var toolGroupIDs: Set<String>?
    public var maxIterations: Int = 10
    public var task: Task<String, Never>?
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0

    public var status: Status {
        get { lock.withLock { _status } }
        set { lock.withLock { _status = newValue } }
    }

    public var result: String {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    public var mailbox: [String] {
        get { lock.withLock { _mailbox } }
        set { lock.withLock { _mailbox = newValue } }
    }

    public func appendMailbox(_ message: String) {
        lock.withLock { _mailbox.append(message) }
    }

    public enum Status: String, Sendable {
        case running, completed, failed
    }

    public init(name: String, prompt: String, projectFolder: String = "") {
        self.name = name
        self.prompt = prompt
        self.projectFolder = projectFolder
    }

    /// 短 ID (用于日志)
    public var shortId: String {
        String(id.uuidString.prefix(8))
    }

    /// 运行时长
    public var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    /// XML 格式完成通知
    public var notification: String {
        let currentStatus: Status = status
        let currentResult: String = result
        return """
        <task-notification>
          <task-id>\(shortId)</task-id>
          <name>\(name)</name>
          <status>\(currentStatus.rawValue)</status>
          <result>\(trim(currentResult, cap: 2000))</result>
          <usage>
            <input_tokens>\(inputTokens)</input_tokens>
            <output_tokens>\(outputTokens)</output_tokens>
            <duration_ms>\(Int(duration * 1000))</duration_ms>
          </usage>
        </task-notification>
        """
    }

    private func trim(_ str: String, cap: Int) -> String {
        str.count <= cap ? str : String(str.prefix(cap)) + "..."
    }
}
