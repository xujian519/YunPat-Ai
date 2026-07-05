import Foundation
import YunPatNetworking

// swiftlint:disable file_length type_body_length
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
    private let caseRuleLoader: CaseRuleLoader

    private let loopGuard: LoopGuard
    private var stuckGuard: StuckGuard
    private let subAgentEngine: SubAgentEngine
    private let frameworkEngine: FrameworkEngine
    private let strategyRegistry: StrategyRegistry
    private var consecutiveReads: Int = 0
    public var planMode: PlanMode = .auto
    public var loopModel: String
    public var workspaceURL: URL?

    public init(
        modelRouter: ModelRouter,
        wikiAdapter: WikiAdapter,
        provider: ModelProvider = .deepseek,
        config: RuntimeConfig = RuntimeConfig(),
        memory: MemoryEngine = MemoryEngine(),
        workspaceURL: URL? = nil
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
        self.caseRuleLoader = .shared
        self.workspaceURL = workspaceURL
        self.loopGuard = LoopGuard(maxIterations: config.maxIterations)
        self.stuckGuard = StuckGuard(
            nudgeThreshold: config.stuckNudgeThreshold,
            giveUpThreshold: config.stuckGiveUpThreshold
        )
        self.subAgentEngine = .shared
        self.frameworkEngine = FrameworkEngine()
        self.strategyRegistry = StrategyRegistry()
        Task { [weak self, modelRouter, provider, loopModel = provider.defaultModel] in
            guard let self else { return }
            await self.strategyRegistry.registerDefaults()
            await self.frameworkEngine.configurePromptExecutor { prompt in
                let chatReq = ChatRequest(
                    model: loopModel, messages: [Message(role: .user, content: prompt)])
                let stream: AsyncThrowingStream<ChatChunk, Error> = try await modelRouter.chat(
                    chatReq, provider: provider)
                var full: String = ""
                for try await chunk in stream {
                    if case .text(let text) = chunk { full += text }
                }
                return full
            }
        }
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
        let toolCount: Int = 0
        var llmCallCount: Int = 0

        state = .running(step: "extracting-facts")
        let facts: StructuredFacts = await factExtractor.extract(from: request)
        // 记录事实到记忆
        await memory.addSessionFact(facts.technicalField, category: .technicalFeature)
        for point in facts.inventionPoints {
            await memory.addSessionFact(point, category: .technicalFeature)
        }

        // 加载已有 CaseContext（如果存在）注入到上下文
        if let workspaceURL, let caseId = workspaceURL.lastPathComponent as String? {
            if let existingContext = await memory.loadCaseContext(caseId) {
                await memory.noteToScratchpad(
                    "已有案件上下文: \(existingContext.technicalField)"
                    + " | 发明点: \(existingContext.inventionPoints.joined(separator: ", "))"
                )
            }
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
        var plan: String = try await buildPlan(facts: facts, rules: rules, traceID: traceID)
        llmCallCount += 1

        // 注入案件级规则
        if let workspaceURL {
            let caseRules: String = await caseRuleLoader.injectableRules(for: workspaceURL, maxTokens: 5000)
            if !caseRules.isEmpty { plan = caseRules + "\n\n" + plan }
        }

        // Step 3b: 法律框架推理 + 结构化推理策略
        let frameworkAnalysis: String = await runFrameworkAnalysis(facts: facts, rules: rules, flow: flow)
        if !frameworkAnalysis.isEmpty {
            plan += "\n\n---\n【法律框架分析】\n\(frameworkAnalysis)"
        }
        let strategyOutput: String = await runReasoningStrategy(facts: facts, rules: rules)
        if !strategyOutput.isEmpty {
            plan += "\n\n---\n【结构化推理】\n\(strategyOutput)"
        }

        // Step 4+5: 执行 → 评估 → 迭代修订
        while revisionCount < config.maxIterations {
            let execReq: UserRequest = UserRequest(content: plan.isEmpty ? facts.technicalField : plan)
            let loopResult: LoopResult = await runExecution(execReq: execReq)
            llmCallCount += 1
            switch loopResult {
            case .completed(let text) where !text.isEmpty:
                // ── [协作点 ④] 中途干预（Guided 模式，首轮执行后）──
                if flow == .guided && revisionCount == 0 {
                    state = .waitingApproval(
                        ApprovalRequest(
                            summary: "执行结果审查",
                            detail: "Agent 已完成首轮执行，是否继续进行质量评估？\n\n\(text.prefix(500))",
                            options: ["继续评估", "直接采纳", "需要修改"]
                        ))
                    return .needsClarification(["请审查执行结果并确认是否继续"])
                }

                // Step 5: EvaluationEngine 质量评估
                state = .running(step: "evaluating")
                let execResult: ExecutionResult = ExecutionResult(artifacts: [text])
                let review: ReviewResult = await evaluator.evaluate(
                    execution: execResult, rules: rules, facts: facts
                )

                do {
                    try await TraceCollector().finishTrace(
                        traceID,
                        summary: TraceSummary(
                            totalCost: 0, totalLatency: Date().timeIntervalSince(startTime),
                            toolCount: toolCount, llmCallCount: llmCallCount
                        )
                    )
                } catch {
                    print("[PatentLoopEngine] Failed to finish trace: \(error)")
                }

                if review.verdict {
                    let reportSuffix: String = review.rubric.map { "\n\n---\n\($0.report())" } ?? ""
                    // 蒸馏会话记忆到 CaseContext（持久化）
                    if let workspaceURL {
                        let caseId: String = workspaceURL.lastPathComponent
                        let context: CaseContext = CaseContext(
                            caseId: caseId,
                            technicalField: facts.technicalField,
                            inventionPoints: facts.inventionPoints,
                            keyReferences: rules.candidates.prefix(5).map(\.title)
                        )
                        do {
                            try await memory.saveCaseContext(context)
                        } catch {
                            print("[PatentLoopEngine] Failed to save case context: \(error)")
                        }
                    }
                    state = .idle
                    return .completed(text + reportSuffix)
                }

                // ── [协作点 ⑤] 最终审核（Guided 模式，评估未通过时）──
                if flow == .guided && !review.issues.isEmpty {
                    let issueList: String = review.issues.enumerated().map { idx, issue in
                        "\(idx + 1). \(issue.severity == .error ? "❌" : "⚠️") \(issue.description)"
                    }.joined(separator: "\n")
                    state = .waitingApproval(
                        ApprovalRequest(
                            summary: "质量审查未通过",
                            detail: "以下问题需要处理：\n\n\(issueList)",
                            options: ["自动修订", "我手动修改", "忽略问题并采纳"]
                        ))
                    return .needsRevision(review.issues)
                }

                // 未通过 — 检查是否还有修订机会
                if revisionCount >= config.maxIterations - 1 {
                    state = .idle
                    return .exceededRevisionLimit(review.issues)
                }

                // 注入修订建议，进入下一轮迭代
                revisionCount += 1
                state = .running(step: "revision-\(revisionCount)")
                let issueSummary: String = review.issues.map { "· \($0.description)" }
                    .joined(separator: "\n")
                plan = """
                    上一版结果未通过质量审查（第\(revisionCount)轮修订），请根据以下问题修订：

                    \(issueSummary)

                    原始结果（节选）：
                    \(text.prefix(2000))
                    """

            case .cancelled:
                state = .idle
                return loopResult
            default:
                break
            }
        }

        return .exceededRevisionLimit([Issue(description: "超过最大修订次数 \(config.maxIterations)")])
    }

    /// Step 3: 使用 LLM 构建策略
    private func buildPlan(facts: StructuredFacts, rules: ApplicableRules, traceID: TraceID) async throws -> String {
        let systemContext: String = try await contextEngine.buildPrompt(
            for: UserRequest(content: "技术领域：\(facts.technicalField)\n问题：\(facts.problem)"),
            flow: .fullAgent
        )
        let prompt: String = """
            \(systemContext)

            ---
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

    /// 解析 LLM 返回的工具调用 JSON 参数为 [String: String] 字典
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

    /// 从 ChatChunk 流中收集文本和工具调用，返回 ModelStepResult
    private static func collectModelStep(
        from stream: AsyncThrowingStream<ChatChunk, Error>
    ) async -> ModelStepResult {
        var full: String = ""
        var deltaArgs: [String: String] = [:]
        var deltaNames: [String: String] = [:]
        var deltaOrder: [String] = []
        var hasToolCalls: Bool = false
        do {
            for try await chunk in stream {
            switch chunk {
            case .text(let text):
                full += text
            case .toolCall(let id, let name, let arguments):
                hasToolCalls = true
                if !deltaOrder.contains(id) { deltaOrder.append(id) }
                deltaNames[id] = name
                deltaArgs[id] = arguments
            case .toolCallDelta(let id, let arguments):
                hasToolCalls = true
                if !deltaOrder.contains(id) { deltaOrder.append(id) }
                deltaArgs[id, default: ""] += arguments
            case .error(let error):
                return .error(error.localizedDescription)
            default:
                break
            }
        }
        } catch {
            return .error(error.localizedDescription)
        }
        if hasToolCalls {
            let calls: [ToolCall] = deltaOrder.map { id in
                ToolCall(
                    id: id,
                    name: deltaNames[id] ?? "unknown",
                    arguments: parseToolArgs(deltaArgs[id] ?? "{}")
                )
            }
            return .toolCalls(calls)
        }
        return .textResponse(full)
    }

    // MARK: - Framework & Strategy Integration

    /// 运行法律框架分析 — 按案件类型选择适用法条框架，逐步执行法律推理
    private func runFrameworkAnalysis(
        facts: StructuredFacts, rules: ApplicableRules, flow: AgentFlow
    ) async -> String {
        let caseType: CaseType = flow == .fullAgent ? .patentability : .drafting
        let frameworks: [ArticleFramework] = await frameworkEngine.listApplicable(caseType: caseType)
        guard !frameworks.isEmpty else { return "" }

        let factStrings: [String] = [facts.technicalField, facts.problem] + facts.inventionPoints
        var results: [String] = []
        for framework in frameworks.prefix(2) {
            var stepOutputs: [String] = []
            for step in framework.steps.prefix(3) {
                if let stepResult = try? await frameworkEngine.executeStep(
                    framework: framework, stepId: step.id, facts: factStrings
                ), let analysis = stepResult.output["analysis"] {
                    stepOutputs.append("### \(step.name)\n\(analysis.prefix(300))")
                }
            }
            if !stepOutputs.isEmpty {
                results.append("#### \(framework.name)\n\(stepOutputs.joined(separator: "\n\n"))")
            }
        }
        return results.joined(separator: "\n\n")
    }

    /// 运行结构化推理策略 — 将事实和规则通过策略引擎结构化
    ///
    /// 流程：写入事实 → ReasoningWalker 图谱步行 → 写入推理链 → 策略选择与执行
    private func runReasoningStrategy(
        facts: StructuredFacts, rules: ApplicableRules
    ) async -> String {
        let blackboard: FactBlackboard = FactBlackboard()
        await blackboard.writeFacts(
            technicalField: facts.technicalField,
            problem: facts.problem,
            inventionPoints: facts.inventionPoints,
            missingInfo: facts.missingInfo
        )

        let kgReport: String = await runKnowledgeGraphWalk(facts: facts, blackboard: blackboard)
        let hasKGChains: Bool = !(await blackboard.reasoningChains).isEmpty

        let strategyName: String
        if hasKGChains {
            strategyName = "kg_reasoning"
        } else if facts.inventionPoints.isEmpty {
            strategyName = "react"
        } else {
            strategyName = "six_step"
        }

        guard let strategy: any ReasoningStrategy = await strategyRegistry.strategy(named: strategyName)
        else { return "" }
        let context: ReasoningContext = ReasoningContext(
            userRequest: UserRequest(
                content: facts.problem.isEmpty ? facts.technicalField : facts.problem),
            blackboard: blackboard, rules: rules
        )
        let output: ReasoningOutput?
        do {
            output = try await strategy.execute(context: context)
        } catch {
            print("[PatentLoopEngine] Reasoning strategy execution failed: \(error)")
            return ""
        }
        guard let output else {
            print("[PatentLoopEngine] Reasoning strategy returned nil")
            return ""
        }

        var result: String = String(output.result.prefix(1200))
        if !kgReport.isEmpty {
            result += "\n\n### 知识图谱覆盖分析\n\(kgReport)"
        }
        return result
    }

    /// 运行知识图谱步行推理 — 从事实出发在 PatentLawKG 上 BFS 构建推理链
    ///
    /// 将 WalkChain 结果转换为 ReasoningChain 写入 blackboard，
    /// 并返回覆盖分析报告供 plan 注入。
    private func runKnowledgeGraphWalk(
        facts: StructuredFacts, blackboard: FactBlackboard
    ) async -> String {
        let walker: ReasoningWalker = ReasoningWalker()
        let walkFacts: [String] = [facts.technicalField, facts.problem] + facts.inventionPoints
        let walkInput: ReasoningWalkInput = ReasoningWalkInput(
            facts: walkFacts, caseType: .patentability, maxDepth: 3, maxChains: 5
        )
        let walkResult: ReasoningWalkResult = await walker.walk(input: walkInput)

        let reasoningChains: [ReasoningChain] = walkResult.chains.compactMap { chain in
            let lastNode: ReasoningChainNode? = chain.nodes.last { $0.nodeType != "relation" }
            let target: String = lastNode?.name ?? "未知"
            let evidenceParts: [String] = [
                chain.legalBasis.lawArticle,
                chain.legalBasis.guidelineRule
            ].compactMap { $0 }
            let evidence: String = evidenceParts.isEmpty
                ? "置信度: \(String(format: "%.2f", chain.confidence))"
                : evidenceParts.joined(separator: "; ")
            return ReasoningChain(from: chain.factRef, toNode: target, evidence: evidence)
        }

        if !reasoningChains.isEmpty {
            let existingConstraints: [RuleConstraint] = await blackboard.ruleConstraints
            await blackboard.writeReasoningResults(
                chains: reasoningChains, constraints: existingConstraints
            )
        }

        guard !walkResult.chains.isEmpty else { return "" }
        var report: String = "覆盖率: \(String(format: "%.0f%%", walkResult.coverage * 100))"
        if !walkResult.gaps.isEmpty {
            report += "\n缺口: " + walkResult.gaps.prefix(5).joined(separator: "; ")
        }
        let highConfidence: [WalkChain] = walkResult.chains.filter { $0.confidence >= 0.6 }
        if !highConfidence.isEmpty {
            report += "\n高置信链: " + highConfidence.map(\.factRef).prefix(3).joined(separator: "; ")
        }
        return report
    }

    /// 用 PatentToolLoop 执行一次分析任务
    private func runExecution(execReq: UserRequest) async -> LoopResult {
        let model: String = loopModel
        let hooks: PatentLoopHooks = PatentLoopHooks(
            buildMessages: { [execReq] in
                [Message(role: .user, content: execReq.content)]
            },
            modelStep: { [modelRouter, provider, model] messages, toolSpecs in
                do {
                    let toolDefs: [ChatToolDefinition] = toolSpecs.map {
                        ChatToolDefinition(name: $0.name, description: $0.description, parameters: $0.parameters)
                    }
                    let chatReq: ChatRequest = ChatRequest(
                        model: model, messages: messages,
                        tools: toolDefs.isEmpty ? nil : toolDefs
                    )
                    let stream: AsyncThrowingStream<ChatChunk, Error> = try await modelRouter.chat(
                        chatReq, provider: provider
                    )
                    return await Self.collectModelStep(from: stream)
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

        let completed: [SubAgent] = await subAgentEngine.waitAllRaw(timeout: 300)
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
