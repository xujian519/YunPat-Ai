import Foundation
import YunPatNetworking

/// 聊天界面适配器 — 封装 PatentToolLoop 提供 ModelRouter 驱动的 Agent 循环
///
/// 保留原公共 API (`run(request:flow:) → LoopResult`) 向后兼容，
/// 内部委托给 PatentToolLoop 驱动。
///
/// 简化入口：`AgentLoopEngine.run(text:modelRouter:)` 一键发送文本。
public actor AgentLoopEngine: LoopEngine {
    public var state: LoopState = .idle

    private let modelRouter: ModelRouter
    private let provider: ModelProvider
    private let loop: PatentToolLoop
    private let contextEngine: ContextEngine

    /// todo 清单更新的 UI 回调（MainActor）
    private var onTodoUpdate: (@Sendable (String) -> Void)?

    /// manifest 是否就绪
    private var manifestReady: Bool = false

    /// 初始化 AgentLoopEngine
    /// - Parameters:
    ///   - modelRouter: 模型路由
    ///   - provider: 默认模型提供商
    public init(modelRouter: ModelRouter, provider: ModelProvider = .deepseek) {
        self.modelRouter = modelRouter
        self.provider = provider
        self.loop = PatentToolLoop()
        self.contextEngine = ContextEngine()

        // 异步注入 capability manifest
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
    ///
    /// 首次 `run()` 调用前可选等待，确保工具注册表已加载。
    /// 支持多 Task 并发等待，使用 Continuation 数组而非单值避免悬挂。
    public func waitUntilReady() async {
        if manifestReady { return }
        await withCheckedContinuation { readyContinuations.append($0) }
    }

    /// 一键入口：用已配置的 ModelRouter 发送文本，无需手动创建 Engine
    ///
    /// - Parameters:
    ///   - text: 用户输入文本
    ///   - modelRouter: 模型路由（决定调用哪个 LLM）
    ///   - provider: 模型提供商（默认 DeepSeek）
    ///   - flow: 对话流程模式（默认 copilot）
    /// - Returns: 循环执行结果
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

    /// 注册 todo 清单更新回调，当 PatentToolLoop 更新检查清单时通知 UI 侧
    ///
    /// - Parameter block: 接收完整 Markdown 清单文本的闭包
    public func setOnTodoUpdate(_ block: @escaping @Sendable (String) -> Void) {
        self.onTodoUpdate = block
    }

    /// 执行一次 Agent 循环
    ///
    /// 内部构建 system prompt → 智能路由模型 → 委托 PatentToolLoop 驱动。
    /// - Parameters:
    ///   - request: 用户请求
    ///   - flow: 对话流程模式
    ///   - model: 指定模型（nil 时自动路由）
    ///   - history: 历史消息列表
    ///   - onStreamChunk: 流式输出回调
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
