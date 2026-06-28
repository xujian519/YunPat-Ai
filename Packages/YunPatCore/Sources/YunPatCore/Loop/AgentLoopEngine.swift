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
        let reg = CapabilityRegistry()
        Task {
            await reg.registerBuiltinCapabilities()
            let manifest = await CapabilityManifest.build(registry: reg, skills: [])
            await self.loop.setManifest(manifest)
        }
    }

    /// 注册 todo 更新回调
    public func setOnTodoUpdate(_ block: @escaping @Sendable (String) -> Void) {
        self.onTodoUpdate = block
    }

    public func run(request: UserRequest, flow: AgentFlow, model: String? = nil, history: [Message] = [], onStreamChunk: PatentLoopHooks.OnStreamChunk? = nil) async throws -> LoopResult {
        state = .running(step: "building-context")
        let systemPrompt = try await contextEngine.buildPrompt(for: request, flow: flow)

        let hooks = makeHooks(systemPrompt: systemPrompt, request: request, model: model ?? provider.defaultModel, history: history, onStreamChunk: onStreamChunk)

        state = .running(step: "executing")
        let exit = await loop.run(
            request: request,
            policy: flow == .copilot ? .chat : .patentFlow,
            hooks: hooks,
            provider: provider
        )

        state = .idle
        return LoopResult(exit: exit)
    }

    // MARK: - Chat Hooks

    private func makeHooks(systemPrompt: String, request: UserRequest, model: String, history: [Message] = [], onStreamChunk: PatentLoopHooks.OnStreamChunk? = nil) -> PatentLoopHooks {
        PatentLoopHooks(
            buildMessages: { [systemPrompt, request, history] in
                var all = [Message(role: .system, content: systemPrompt)]
                all.append(contentsOf: history)
                all.append(Message(role: .user, content: request.content))
                return all
            },
            modelStream: { [modelRouter, provider, model] messages, _ in
                let chatReq = ChatRequest(model: model, messages: messages)
                let rawStream = try await modelRouter.chat(chatReq, provider: provider)
                return AsyncThrowingStream { continuation in
                    Task {
                        do {
                            var accumulated = ""
                            for try await chunk in rawStream {
                                switch chunk {
                                case .text(let t):
                                    accumulated += t
                                    continuation.yield(.textDelta(t))
                                case .finish:
                                    continuation.yield(.done(accumulated))
                                    continuation.finish()
                                    return
                                case .error(let e):
                                    continuation.yield(.error(e.localizedDescription))
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
                let ctx = ToolContext(toolId: call.id, projectFolder: "", selectedProvider: provider)
                return await ToolDispatch.executeCall(call, ctx: ctx)
            },
            executeBatch: { [provider] calls, ctx in
                var results: [ToolEnvelope] = []
                for call in calls {
                    let toolCtx = ToolContext(toolId: call.id, projectFolder: ctx.projectFolder, selectedProvider: provider)
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
        case .finalResponse(let s): self = .completed(s)
        case .iterationCapReached(let s): self = .completed(s)
        case .toolRejected(let s): self = .exceededRevisionLimit([Issue(severity: .error, description: s)])
        case .cancelled: self = .cancelled
        case .endedBySurface(let e):
            if e.kind == .clarify {
                self = .needsClarification([e.summary])
            } else {
                self = .completed(e.summary)
            }
        case .overBudget(let s): self = .completed(s)
        }
    }
}
