import Foundation
import YunPatNetworking

/// Chat surface adapter for PatentToolLoop
///
/// 保留原公共 API (`run(request:flow:) → LoopResult`) 向后兼容，
/// 内部委托给 PatentToolLoop 驱动。
public actor AgentLoopEngine: LoopEngine {
    public var state: LoopState = .idle

    private let modelRouter: ModelRouter
    private let provider: ModelProvider
    private let loop: PatentToolLoop
    private let contextEngine: ContextEngine

    /// todo 清单更新的 UI 回调（MainActor）
    private var onTodoUpdate: (@Sendable (String) -> Void)?

    public init(modelRouter: ModelRouter, provider: ModelProvider = .deepseek) {
        self.modelRouter = modelRouter
        self.provider = provider
        self.loop = PatentToolLoop()
        self.contextEngine = ContextEngine()

        // 生成并注入 frozen capability manifest（异步）
        let reg: CapabilityRegistry = CapabilityRegistry()
        Task {
            await reg.registerBuiltinCapabilities()
            let manifest: CapabilityManifest = await CapabilityManifest.build(registry: reg, skills: [])
            await self.loop.setManifest(manifest)
        }
    }

    /// 注册 todo 更新回调
    public func setOnTodoUpdate(_ block: @escaping @Sendable (String) -> Void) {
        self.onTodoUpdate = block
    }

    public func run(
        request: UserRequest, flow: AgentFlow, model: String? = nil,
        history: [Message] = [],
        onStreamChunk: PatentLoopHooks.OnStreamChunk? = nil
    ) async throws -> LoopResult {
        state = .running(step: "building-context")
        let systemPrompt: String = try await contextEngine.buildPrompt(for: request, flow: flow)

        // 智能路由：无显式指定模型时按任务特征自动选择
        let effectiveModel: String
        if let specifiedModel = model {
            effectiveModel = specifiedModel
        } else {
            let category: SmartModelRouter.TaskCategory = SmartModelRouter.classify(request)
            effectiveModel = SmartModelRouter.selectModel(for: category, preferred: provider)
        }

        let hooks: PatentLoopHooks = makeHooks(
            systemPrompt: systemPrompt, request: request,
            model: effectiveModel, history: history, onStreamChunk: onStreamChunk)

        state = .running(step: "executing")
        let exit: LoopExit = await loop.run(
            request: request,
            policy: flow == .copilot ? .chat : .patentFlow,
            hooks: hooks,
            provider: provider
        )

        state = .idle
        return LoopResult(exit: exit)
    }

    // MARK: - Chat Hooks

    private func makeHooks(
        systemPrompt: String, request: UserRequest, model: String,
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
            modelStream: { [modelRouter, provider, model] messages, _ in
                let chatReq: ChatRequest = ChatRequest(model: model, messages: messages)
                let rawStream: AsyncThrowingStream<ChatChunk, Error> =
                    try await modelRouter
                    .chat(chatReq, provider: provider)
                return AsyncThrowingStream { continuation in
                    Task {
                        do {
                            var accumulated: String = ""
                            for try await chunk in rawStream {
                                switch chunk {
                                case .text(let text):
                                    accumulated += text
                                    continuation.yield(.textDelta(text))
                                case .finish:
                                    continuation.yield(.done(accumulated))
                                    continuation.finish()
                                    return
                                case .error(let error):
                                    continuation.yield(.error(error.localizedDescription))
                                    continuation.finish()
                                    return
                                default:
                                    break
                                }
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
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
}

// MARK: - LoopResult → LoopExit 转换

extension LoopResult {
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
