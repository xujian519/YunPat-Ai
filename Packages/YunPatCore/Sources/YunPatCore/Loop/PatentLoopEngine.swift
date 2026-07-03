import Foundation
import YunPatNetworking

// swiftlint:disable type_body_length
/// 专利五步流程引擎 — 封装 PatentToolLoop 实现专利分析全流程
///
/// 步骤：
/// 1. 从 UserRequest 提取结构化事实（FactExtractor）
/// 2. 检索适用法规/判例（RuleEngine）
/// 3. 构建策略（LLM 生成 plan）
/// 4. 执行策略（委托 PatentToolLoop）
/// 5. 评估结果 / 迭代修订
///
/// 支持三路并行分析（新颖性 / 创造性 / 侵权判定）。
public actor PatentLoopEngine: LoopEngine {
    public var state: LoopState = .idle
    private let modelRouter: ModelRouter
    private let provider: ModelProvider
    private let wikiAdapter: WikiAdapter
    private let ruleEngine: RuleEngine
    private let factExtractor: FactExtractor
    private let contextEngine: ContextEngine
    private let innerLoop: PatentToolLoop
    private let evaluator: EvaluationEngine
    private let config: RuntimeConfig
    private let memory: MemoryEngine

    private let loopGuard: LoopGuard
    private var stuckGuard: StuckGuard
    private let subAgentEngine: SubAgentEngine
    private var consecutiveReads: Int = 0
    public var planMode: PlanMode = .auto
    public var loopModel: String

    public init(
        modelRouter: ModelRouter,
        wikiAdapter: WikiAdapter,
        provider: ModelProvider = .deepseek,
        config: RuntimeConfig = RuntimeConfig(),
        memory: MemoryEngine = MemoryEngine()
    ) {
        self.modelRouter = modelRouter
        self.wikiAdapter = wikiAdapter
        self.provider = provider
        self.loopModel = provider.defaultModel
        self.ruleEngine = RuleEngine(adapter: wikiAdapter)
        self.factExtractor = FactExtractor()
        self.contextEngine = ContextEngine()
        self.innerLoop = PatentToolLoop()
        self.evaluator = EvaluationEngine()
        self.config = config
        self.memory = memory
        self.loopGuard = LoopGuard(maxIterations: config.maxIterations)
        self.stuckGuard = StuckGuard(
            nudgeThreshold: config.stuckNudgeThreshold,
            giveUpThreshold: config.stuckGiveUpThreshold
        )
        self.subAgentEngine = .shared
    }

    // 执行五步专利分析流程
    //
    // 流程：提取事实 → 检索规则 → 确认规则（Guided 模式）→ 迭代执行 → 返回结果
    // - Parameters:
    //   - request: 用户请求
    //   - flow: 对话模式（guided 模式下会暂停等待规则确认）
    //   - model: 指定模型（nil 时使用 loopModel）
    //   - history: 历史消息（当前未使用）
    //   - onStreamChunk: 流式输出回调（当前未使用）
    // swiftlint:disable:next function_body_length
    public func run(
        request: UserRequest, flow: AgentFlow, model: String? = nil,
        history: [Message] = [],
        onStreamChunk: PatentLoopHooks.OnStreamChunk? = nil
    ) async throws -> LoopResult {
        var revisionCount: Int = 0
        stuckGuard.resetAll()
        consecutiveReads = 0
        let traceID: TraceID = await TraceCollector().startTrace()
        let startTime: Date = Date()
        var toolCount: Int = 0
        var llmCallCount: Int = 0

        state = .running(step: "extracting-facts")
        let facts: StructuredFacts = await factExtractor.extract(from: request)
        // 记录事实到记忆
        await memory.addSessionFact(facts.technicalField, category: .technicalFeature)
        for point in facts.inventionPoints {
            await memory.addSessionFact(point, category: .technicalFeature)
        }
        if !facts.missingInfo.isEmpty, flow == .guided {
            return .needsClarification(facts.missingInfo)
        }

        state = .running(step: "retrieving-rules")
        let rulesStepStart: Date = Date()
        let rules: ApplicableRules = try await ruleEngine.retrieveRules(for: facts)
        await TraceCollector().recordCapability(
            CapabilityTrace(
                capability: "knowledge.search", tool: "retrieveRules",
                latency: Date().timeIntervalSince(rulesStepStart)
            ),
            parent: traceID
        )
        // 记录规则到记忆
        for candidate in rules.candidates.prefix(5) {
            await memory.addSessionFact(candidate.title, category: .legalRule)
        }

        // ── [协作点 ②] 规则确认（Guided 模式）──
        if flow == .guided && !rules.candidates.isEmpty {
            let candidateList: String = rules.candidates.prefix(5).map { candidate in
                "\(candidate.sourceLevel <= 2 ? "📜" : "📋") \(candidate.title)"
            }.joined(separator: "\n")
            state = .waitingApproval(
                ApprovalRequest(
                    summary: "规则确认",
                    detail: "以下规则适用于当前案件，是否确认？\n\n\(candidateList)",
                    options: ["确认执行", "修改规则", "跳过规则"]
                ))
            return .needsClarification(
                ["请确认适用规则: \(rules.candidates.prefix(3).map(\.title).joined(separator: "、"))"]
            )
        }

        // Step 3: 规划 — 生成策略并注入执行
        state = .running(step: "planning")
        let plan: String = try await buildPlan(facts: facts, rules: rules, traceID: traceID)

        // Step 4: 执行（将策略注入执行请求）
        while revisionCount < config.maxIterations {
            let execReq: UserRequest = UserRequest(content: plan.isEmpty ? facts.technicalField : plan)
            let loopResult: LoopResult = await runExecution(execReq: execReq)
            switch loopResult {
            case .completed(let text) where !text.isEmpty:
                // Step 5: 评估 — TODO: EvaluationEngine 集成
                try? await TraceCollector().finishTrace(
                    traceID,
                    summary: TraceSummary(
                        totalCost: 0, totalLatency: Date().timeIntervalSince(startTime),
                        toolCount: toolCount, llmCallCount: llmCallCount
                    )
                )
                state = .idle
                return loopResult
            case .cancelled:
                state = .idle
                return loopResult
            default:
                break
            }
            revisionCount += 1
            state = .running(step: "revision-\(revisionCount)")
        }

        return .exceededRevisionLimit([Issue(description: "超过最大修订次数 \(config.maxIterations)")])
    }

    /// 执行一次修订迭代
    private func executeRevision(
        revisionCount: Int, facts: StructuredFacts, rules: ApplicableRules,
        traceID: TraceID, startTime: Date, flow: AgentFlow
    ) async throws -> LoopResult? {
        state = .running(step: "planning")
        let plan: String = try await buildPlan(facts: facts, rules: rules, traceID: traceID)
        guard !plan.isEmpty else { return nil }

        state = .running(step: "executing-plan")
        let execReq: UserRequest = UserRequest(content: plan)
        let result: LoopResult = await runExecution(execReq: execReq)

        switch result {
        case .completed(let text) where text.contains("exceeded") || text.contains("error"):
            // Run a second pass
            let revisedPlan: String = try await buildPlan(facts: facts, rules: rules, traceID: traceID)
            let retryReq: UserRequest = UserRequest(content: revisedPlan)
            return await runExecution(execReq: retryReq)
        default:
            return result
        }
    }

    /// Step 3: 使用 LLM 构建策略
    private func buildPlan(facts: StructuredFacts, rules: ApplicableRules, traceID: TraceID) async throws -> String {
        let prompt: String = """
            你是一位资深中国专利代理人。基于以下信息制定策略：

            技术领域：\(facts.technicalField)
            问题：\(facts.problem)
            发明点：\(facts.inventionPoints.joined(separator: "; "))

            适用规则：
            \(rules.injectableTokens(maxTokens: 2000))

            请制定一个包含以下内容的策略：
            1. 核心答辩/撰写思路
            2. 关键技术特征对比
            3. 风险点和应对
            """

        let startTime: Date = Date()
        let chatReq: ChatRequest = ChatRequest(
            model: loopModel,
            messages: [Message(role: .user, content: prompt)]
        )
        let stream: AsyncThrowingStream<ChatChunk, Error> = try await modelRouter.chat(
            chatReq, provider: provider
        )
        var full: String = ""
        for try await chunk in stream {
            if case .text(let text) = chunk { full += text }
        }

        // 记录 PromptTrace（系统提示词 hash 脱敏）
        let promptHash: String = Self.sha256(prompt.prefix(200))
        await TraceCollector().recordPrompt(
            PromptTrace(
                systemPromptHash: promptHash,
                cost: 0,
                latency: Date().timeIntervalSince(startTime),
                model: loopModel
            ),
            parent: traceID
        )

        return full.isEmpty ? "策略制定完成" : full
    }

    private static func sha256(_ text: some StringProtocol) -> String {
        var hasher: Hasher = Hasher()
        hasher.combine(String(text))
        return String(format: "%016lx", hasher.finalize())
    }

    /// 用 PatentToolLoop 执行一次分析任务
    private func runExecution(execReq: UserRequest) async -> LoopResult {
        let model: String = loopModel
        let hooks: PatentLoopHooks = PatentLoopHooks(
            buildMessages: { [execReq] in
                [Message(role: .user, content: execReq.content)]
            },
            modelStep: { [modelRouter, provider, model] messages, _ in
                do {
                    let chatReq: ChatRequest = ChatRequest(model: model, messages: messages)
                    let stream: AsyncThrowingStream<ChatChunk, Error> = try await modelRouter.chat(
                        chatReq, provider: provider
                    )
                    var full: String = ""
                    for try await chunk in stream {
                        if case .text(let text) = chunk { full += text }
                    }
                    return .textResponse(full)
                } catch {
                    return .error(error.localizedDescription)
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
                        toolId: call.id, projectFolder: ctx.projectFolder,
                        selectedProvider: provider
                    )
                    results.append(await ToolDispatch.executeCall(call, ctx: toolCtx))
                }
                return results
            }
        )
        let exit: LoopExit = await innerLoop.run(
            request: execReq,
            policy: .patentFlow,
            hooks: hooks,
            provider: provider
        )
        return LoopResult(exit: exit)
    }

    /// 专利三路并行分析：新颖性 / 创造性 / 侵权判定
    ///
    /// 通过 SubAgentEngine 同时启动三个子任务并行分析，
    /// 等待全部完成（超时 300s）后合并为汇总报告。
    /// - Parameters:
    ///   - request: 包含技术方案的请求
    ///   - provider: 模型提供商
    /// - Returns: 三路分析汇总结果
    public func runParallelAnalysis(
        request: UserRequest,
        provider: ModelProvider = .deepseek
    ) async throws -> LoopResult {
        state = .running(step: "parallel-analysis")
        await subAgentEngine.reset()

        let tasks: [(name: String, prompt: String)] = [
            (
                "新颖性分析",
                "分析以下技术方案的新颖性，评估是否具备专利法第22条第2款规定的新颖性。"
                    + "\n\n\(request.content)"
            ),
            (
                "创造性分析",
                "分析以下技术方案的创造性，用三步法评估是否具备专利法第22条第3款规定的创造性。"
                    + "\n\n\(request.content)"
            ),
            (
                "侵权判定",
                "基于以下技术方案，分析潜在侵权风险，判定是否落入已知专利的保护范围。"
                    + "\n\n\(request.content)"
            )
        ]

        _ = await subAgentEngine.spawnBatch(
            tasks: tasks,
            projectFolder: "",
            modelRouter: modelRouter,
            provider: provider
        )

        let completed: [SubAgent] = await subAgentEngine.waitAll(timeout: 300)
        let notifications: [String] = completed.map { $0.notification }

        state = .idle
        let summary: String = """
            专利三路并行分析完成 (共 \(completed.count) 路):

            \(notifications.joined(separator: "\n\n"))
            """
        return .completed(summary)
    }
}
// swiftlint:enable type_body_length
