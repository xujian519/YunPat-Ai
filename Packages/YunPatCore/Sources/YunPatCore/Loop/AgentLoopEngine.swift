import Foundation
import YunPatNetworking

/// 聊天界面适配器 — 封装 PatentToolLoop 提供 ModelRouter 驱动的 Agent 循环
///
/// 简化入口：`AgentLoopEngine.run(text:modelRouter:)` 一键发送文本。
public actor AgentLoopEngine: LoopEngine {
    public var state: LoopState = .idle

    private let modelRouter: ModelRouter
    private let defaultProvider: ModelProvider
    private let loop: PatentToolLoop
    private let contextEngine: ContextEngine
    private let routingEngine: RoutingEngine

    private var onTodoUpdate: (@Sendable (String) -> Void)?

    private var manifestReady: Bool = false

    public init(
        modelRouter: ModelRouter,
        provider: ModelProvider = .deepseek,
        routingEngine: RoutingEngine? = nil
    ) {
        self.modelRouter = modelRouter
        self.defaultProvider = provider
        self.routingEngine = routingEngine ?? RoutingEngine(
            fallbackService: FallbackChainService.shared
        )
        self.loop = PatentToolLoop()
        self.contextEngine = ContextEngine()

        let reg: CapabilityRegistry = CapabilityRegistry()
        Task { [weak self] in
            guard let self else { return }
            await reg.registerBuiltinCapabilities()
            let manifest: CapabilityManifest = await CapabilityManifest.build(registry: reg, skills: [])
            await self.loop.setManifest(manifest)
            await self.markManifestReady()
        }
    }

    private var readyContinuations: [CheckedContinuation<Void, Never>] = []

    private func markManifestReady() {
        manifestReady = true
        for continuation in readyContinuations { continuation.resume() }
        readyContinuations.removeAll()
    }

    /// 等待 Capability manifest 异步加载就绪
    public func waitUntilReady() async {
        if manifestReady { return }
        await withCheckedContinuation { readyContinuations.append($0) }
    }

    /// 一键入口：用已配置的 ModelRouter 发送文本，无需手动创建 Engine
    public static func run(
        text: String,
        modelRouter: ModelRouter,
        provider: ModelProvider = .deepseek,
        flow: AgentFlow = .copilot
    ) async throws -> LoopResult {
        let engine: AgentLoopEngine = AgentLoopEngine(modelRouter: modelRouter, provider: provider)
        await engine.waitUntilReady()
        return try await engine.run(request: UserRequest(content: text), flow: flow)
    }

    /// 注册 todo 清单更新回调
    public func setOnTodoUpdate(_ block: @escaping @Sendable (String) -> Void) {
        self.onTodoUpdate = block
    }

    /// 执行一次 Agent 循环
    public func run(
        request: UserRequest, flow: AgentFlow, model: String? = nil,
        history: [Message] = [],
        onStreamChunk: PatentLoopHooks.OnStreamChunk? = nil
    ) async throws -> LoopResult {
        state = .running(step: "building-context")
        let systemPrompt: String = try await contextEngine.buildPrompt(for: request, flow: flow)

        let effectiveModel: String
        if let specifiedModel = model {
            effectiveModel = specifiedModel
        } else {
            let category: SmartModelRouter.TaskCategory = SmartModelRouter.classify(request)
            effectiveModel = SmartModelRouter.selectModel(for: category, preferred: defaultProvider)
        }

        let hooks: PatentLoopHooks = makeHooks(
            systemPrompt: systemPrompt, request: request,
            model: effectiveModel, provider: defaultProvider,
            history: history, onStreamChunk: onStreamChunk)

        state = .running(step: "executing")
        let exit: LoopExit = await loop.run(
            request: request,
            policy: flow == .copilot ? .chat : .patentFlow,
            hooks: hooks,
            provider: defaultProvider
        )

        state = .idle
        return LoopResult(exit: exit)
    }

    /// 带智能路由的执行方法
    public func runWithRouting(
        request: UserRequest, flow: AgentFlow, model: String? = nil,
        provider: ModelProvider? = nil,
        caseId: String? = nil,
        history: [Message] = [],
        onStreamChunk: PatentLoopHooks.OnStreamChunk? = nil
    ) async throws -> LoopResult {
        state = .running(step: "building-context")
        let systemPrompt: String = try await contextEngine.buildPrompt(for: request, flow: flow)

        let effectiveProvider: ModelProvider
        let effectiveModel: String
        if let specifiedModel = model {
            effectiveModel = specifiedModel
            effectiveProvider = provider ?? defaultProvider
        } else if let specifiedProvider = provider {
            let category: SmartModelRouter.TaskCategory = SmartModelRouter.classify(request)
            effectiveModel = SmartModelRouter.selectModel(for: category, preferred: specifiedProvider)
            effectiveProvider = specifiedProvider
        } else {
            let decision: RoutingDecision = await routingEngine.route(
                RoutingRequest(content: request.content, caseId: caseId)
            )
            effectiveModel = decision.model
            effectiveProvider = decision.provider
        }

        let hooks: PatentLoopHooks = makeHooks(
            systemPrompt: systemPrompt, request: request,
            model: effectiveModel, provider: effectiveProvider,
            caseId: caseId, history: history, onStreamChunk: onStreamChunk)

        state = .running(step: "executing")
        let exit: LoopExit = await loop.run(
            request: request,
            policy: flow == .copilot ? .chat : .patentFlow,
            hooks: hooks,
            provider: effectiveProvider
        )

        state = .idle
        return LoopResult(exit: exit)
    }

    private func makeHooks(
        systemPrompt: String, request: UserRequest, model: String,
        provider: ModelProvider, caseId: String? = nil,
        history: [Message] = [],
        onStreamChunk: PatentLoopHooks.OnStreamChunk? = nil
    ) -> PatentLoopHooks {
        PatentLoopHooks(
            buildMessages: { [systemPrompt, request, history] in
                var all: [Message] = [Message(role: .system, content: systemPrompt)]
                all.append(contentsOf: history)
                all.append(Message(role: .user, content: request.content))
                return all
            },
            modelStream: { [modelRouter, provider, model, caseId, routingEngine] messages, toolSpecs in
                let toolDefs: [ChatToolDefinition] = toolSpecs.map {
                    ChatToolDefinition(name: $0.name, description: $0.description, parameters: $0.parameters)
                }
                let chatReq: ChatRequest = ChatRequest(
                    model: model, messages: messages,
                    tools: toolDefs.isEmpty ? nil : toolDefs
                )
                let rawStream: AsyncThrowingStream<ChatChunk, Error> =
                    try await modelRouter
                    .chat(chatReq, provider: provider)
                return AsyncThrowingStream { continuation in
                    let config: StreamConfig = StreamConfig(
                        caseId: caseId, provider: provider,
                        model: model, routingEngine: routingEngine
                    )
                    Self.processStream(
                        rawStream: rawStream, config: config,
                        into: continuation
                    )
                }
            },
            executeTool: { [provider] call in
                let ctx: ToolContext = ToolContext(toolId: call.id, projectFolder: "", selectedProvider: provider)
                return await ToolDispatch.executeCall(call, ctx: ctx)
            },
            executeBatch: { [provider] calls, ctx in
                var results: [ToolEnvelope] = []
                for call in calls {
                    let toolCtx: ToolContext = ToolContext(
                        toolId: call.id,
                        projectFolder: ctx.projectFolder,
                        selectedProvider: provider)
                    results.append(await ToolDispatch.executeCall(call, ctx: toolCtx))
                }
                return results
            },
            onTodoUpdate: { [onTodoUpdate = self.onTodoUpdate] checklist in
                onTodoUpdate?(checklist)
            },
            onStreamChunk: onStreamChunk
        )
    }

    private static func parseToolArgs(_ json: String) -> [String: String] {
        guard let data: Data = json.data(using: .utf8),
              let dict: [String: Any] = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict.reduce(into: [String: String]()) { result, entry in
            if let str: String = entry.value as? String {
                result[entry.key] = str
            } else if let num: NSNumber = entry.value as? NSNumber {
                result[entry.key] = num.stringValue
            } else if let data: Data = try? JSONSerialization.data(withJSONObject: entry.value),
                      let str: String = String(data: data, encoding: .utf8) {
                result[entry.key] = str
            }
        }
    }
}

// MARK: - Stream Types

extension AgentLoopEngine {
    struct StreamConfig {
        let caseId: String?
        let provider: ModelProvider
        let model: String
        let routingEngine: RoutingEngine
    }
}

// MARK: - Stream Processing

extension AgentLoopEngine {
    private static func processStream(
        rawStream: AsyncThrowingStream<ChatChunk, Error>,
        config: StreamConfig,
        into continuation: AsyncThrowingStream<ModelStepChunk, Error>.Continuation
    ) {
        Task {
            do {
                var accumulated: String = ""
                var deltaArgs: [String: String] = [:]
                var deltaNames: [String: String] = [:]
                var deltaOrder: [String] = []
                var hasToolCalls: Bool = false
                for try await chunk in rawStream {
                    switch chunk {
                    case .text(let text):
                        accumulated += text
                        continuation.yield(.textDelta(text))
                    case .toolCall(let id, let name, let arguments):
                        hasToolCalls = true
                        if !deltaOrder.contains(id) { deltaOrder.append(id) }
                        deltaNames[id] = name
                        deltaArgs[id] = arguments
                    case .toolCallDelta(let id, let arguments):
                        hasToolCalls = true
                        if !deltaOrder.contains(id) { deltaOrder.append(id) }
                        deltaArgs[id, default: ""] += arguments
                    case .finish(let reason, let usage):
                        if let usage {
                            await config.routingEngine.reportUsage(
                                caseId: config.caseId, provider: config.provider, model: config.model, usage: usage
                            )
                        }
                        flushToolCalls(deltaOrder, deltaNames, deltaArgs, into: continuation)
                        if !hasToolCalls && reason != .toolCalls {
                            continuation.yield(.done(accumulated))
                        }
                        continuation.finish()
                        return
                    case .error(let error):
                        continuation.yield(.error(error.localizedDescription))
                        continuation.finish()
                        return
                    }
                }
                flushToolCalls(deltaOrder, deltaNames, deltaArgs, into: continuation)
                if !hasToolCalls {
                    continuation.yield(.done(accumulated))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private static func flushToolCalls(
        _ order: [String],
        _ names: [String: String],
        _ args: [String: String],
        into continuation: AsyncThrowingStream<ModelStepChunk, Error>.Continuation
    ) {
        for id in order {
            let name: String = names[id] ?? "unknown"
            let parsed: [String: String] = parseToolArgs(args[id] ?? "{}")
            continuation.yield(.toolCall(ToolCall(id: id, name: name, arguments: parsed)))
        }
    }
}

// MARK: - LoopResult → LoopExit 转换

extension LoopResult {
    /// 将 LoopExit 转换为 LoopResult（桥接新旧退出类型）
    public init(exit: LoopExit) {
        switch exit {
        case .finalResponse(let text): self = .completed(text)
        case .iterationCapReached(let text): self = .completed(text)
        case .toolRejected(let text): self = .exceededRevisionLimit([Issue(severity: .error, description: text)])
        case .cancelled: self = .cancelled
        case .endedBySurface(let event):
            if event.kind == .clarify {
                self = .needsClarification([event.summary])
            } else {
                self = .completed(event.summary)
            }
        case .overBudget(let text): self = .completed(text)
        }
    }
}
