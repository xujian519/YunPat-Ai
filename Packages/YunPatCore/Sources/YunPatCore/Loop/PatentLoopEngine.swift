import Foundation
import YunPatNetworking

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

    private let loopGuard: LoopGuard
    private var stuckGuard: StuckGuard
    private let subAgentEngine: SubAgentEngine
    private var consecutiveReads = 0
    public var planMode: PlanMode = .auto
    public var loopModel: String

    public init(
        modelRouter: ModelRouter,
        wikiAdapter: WikiAdapter,
        provider: ModelProvider = .deepseek,
        config: RuntimeConfig = RuntimeConfig()
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
        self.loopGuard = LoopGuard(maxIterations: config.maxIterations)
        self.stuckGuard = StuckGuard(nudgeThreshold: config.stuckNudgeThreshold, giveUpThreshold: config.stuckGiveUpThreshold)
        self.subAgentEngine = .shared
    }

    /// 五步专利流程 — 基于 PatentToolLoop + PlanMode
    public func run(request: UserRequest, flow: AgentFlow, model: String? = nil, history: [Message] = [], onStreamChunk: PatentLoopHooks.OnStreamChunk? = nil) async throws -> LoopResult {
        var revisionCount = 0
        stuckGuard.resetAll()
        consecutiveReads = 0
        let traceID = await TraceCollector().startTrace()
        let startTime = Date()
        var toolCount = 0
        var llmCallCount = 0

        state = .running(step: "extracting-facts")
        let facts = await factExtractor.extract(from: request)
        if !facts.missingInfo.isEmpty, flow == .guided {
            return .needsClarification(facts.missingInfo)
        }

        state = .running(step: "retrieving-rules")
        let rulesStepStart = Date()
        let rules = try await ruleEngine.retrieveRules(for: facts)
        await TraceCollector().recordCapability(
            CapabilityTrace(capability: "knowledge.search", tool: "retrieveRules", latency: Date().timeIntervalSince(rulesStepStart)),
            parent: traceID
        )

        // ── [协作点 ②] 规则确认（Guided 模式）──
        if flow == .guided && !rules.candidates.isEmpty {
            let candidateList = rules.candidates.prefix(5).map { c in
                "\(c.sourceLevel <= 2 ? "📜" : "📋") \(c.title)"
            }.joined(separator: "\n")
            state = .waitingApproval(ApprovalRequest(
                summary: "规则确认",
                detail: "以下规则适用于当前案件，是否确认？\n\n\(candidateList)",
                options: ["确认执行", "修改规则", "跳过规则"]
            ))
            return .needsClarification(["请确认适用规则: \(rules.candidates.prefix(3).map(\.title).joined(separator: "、"))"])
        }

        while revisionCount < config.maxIterations {
            if let _ = loopGuard.checkIteration(revisionCount) {
                state = .running(step: "iterating(\(revisionCount)/\(config.maxIterations))")
            }
            if let _ = loopGuard.checkConsecutiveReads(consecutiveReads) {
                consecutiveReads = 0
            }

            state = .running(step: "planning")
            let planText = try await buildPlan(facts: facts, rules: rules)
            _ = ExecutionPlan(
                strategy: planText,
                steps: [PlanStep(
                    name: "执行",
                    description: "根据规则分析事实并生成输出",
                    boundRule: rules.candidates.first?.wikilink
                )]
            )

            switch planMode {
            case .readOnly:
                state = .idle
                return .completed(planText)

            case .interactive:
                state = .waitingApproval(
                    ApprovalRequest(
                        summary: "策略审批",
                        detail: planText,
                        options: ["确认执行", "修改策略", "仅保留方案"]
                    )
                )
                return .needsClarification(["请确认执行策略: \(String(planText.prefix(200)))"])

            case .auto:
                break
            }

            state = .running(step: "executing")
            let contextPrompt = """
            技术领域：\(facts.technicalField)
            问题：\(facts.problem)
            发明点：\(facts.inventionPoints.joined(separator: "; "))

            \(rules.injectableTokens(maxTokens: 2000))
            """
            let execReq = UserRequest(content: contextPrompt)
            let execResult = await runExecution(execReq: execReq)
            let artifacts: [String] = {
                if case .completed(let t) = execResult { return [t] }
                return []
            }()
            let result = ExecutionResult(
                stepResults: [StepResult(stepName: "execute", output: artifacts.first ?? "")],
                artifacts: artifacts
            )

            // ── [协作点 ④] 中途干预（Guided 模式，执行后暂停确认）──
            if flow == .guided && !artifacts.isEmpty {
                let preview = String(artifacts.first?.prefix(300) ?? "")
                state = .waitingApproval(ApprovalRequest(
                    summary: "执行结果预览",
                    detail: "第 \(revisionCount + 1) 轮执行完成：\n\n\(preview)\n\n是否继续审查？",
                    options: ["继续审查", "修改需求", "采纳结果"]
                ))
                if revisionCount == 0 {
                    return .needsClarification(["执行预览: \(preview)"])
                }
            }

            state = .running(step: "reviewing")
            let review = await evaluator.evaluate(execution: result, rules: rules, facts: facts)
            if review.verdict {
                state = .idle
                let prefix = artifacts.joined(separator: "\n\n")
                let summary = TraceSummary(
                    totalCost: 0, totalLatency: Date().timeIntervalSince(startTime),
                    toolCount: toolCount, llmCallCount: llmCallCount
                )
                try? await TraceCollector().finishTrace(traceID, summary: summary)
                if let rubric = review.rubric {
                    return .completed(prefix + "\n\n---\n\(rubric.report())")
                }
                return .completed(prefix)
            }

            // ── [协作点 ⑤] 最终审核确认（Guided 模式，审查未通过）──
            if flow == .guided {
                state = .waitingApproval(ApprovalRequest(
                    summary: "审查未通过",
                    detail: review.report,
                    options: ["重新执行", "忽略问题继续", "放弃"]
                ))
                return .needsRevision(review.issues)
            }
            revisionCount += 1
        }

        state = .idle
        let exceededMsg = loopGuard.checkIteration(config.maxIterations + 1)
            ?? "超过最大修订次数 \(config.maxIterations)"
        let result = LoopResult.exceededRevisionLimit([Issue(description: exceededMsg)])
        let summary = TraceSummary(
            totalCost: 0, totalLatency: Date().timeIntervalSince(startTime),
            toolCount: toolCount, llmCallCount: llmCallCount
        )
        try? await TraceCollector().finishTrace(traceID, summary: summary)
        return result
    }

    /// Step 3: 使用 LLM 构建策略
    private func buildPlan(facts: StructuredFacts, rules: ApplicableRules) async throws -> String {
        let prompt = """
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

        let chatReq = ChatRequest(
            model: loopModel,
            messages: [Message(role: .user, content: prompt)]
        )
        let stream = try await modelRouter.chat(chatReq, provider: provider)
        var full = ""
        for try await chunk in stream {
            if case .text(let t) = chunk { full += t }
        }
        return full.isEmpty ? "策略制定完成" : full
    }

    /// 用 PatentToolLoop 执行一次分析任务
    private func runExecution(execReq: UserRequest) async -> LoopResult {
        let model = loopModel
        let hooks = PatentLoopHooks(
            buildMessages: { [execReq] in
                [Message(role: .user, content: execReq.content)]
            },
            modelStep: { [modelRouter, provider, model] messages, _ in
                do {
                    let chatReq = ChatRequest(model: model, messages: messages)
                    let stream = try await modelRouter.chat(chatReq, provider: provider)
                    var full = ""
                    for try await chunk in stream {
                        if case .text(let t) = chunk { full += t }
                    }
                    return .textResponse(full)
                } catch {
                    return .error(error.localizedDescription)
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
            }
        )
        let exit = await innerLoop.run(
            request: execReq,
            policy: .patentFlow,
            hooks: hooks,
            provider: provider
        )
        return LoopResult(exit: exit)
    }

    /// 专利三路并行分析: 新颖性 / 创造性 / 侵权判定
    public func runParallelAnalysis(
        request: UserRequest,
        provider: ModelProvider = .deepseek
    ) async throws -> LoopResult {
        state = .running(step: "parallel-analysis")
        await subAgentEngine.reset()

        let tasks: [(name: String, prompt: String)] = [
            ("新颖性分析", "分析以下技术方案的新颖性，评估是否具备专利法第22条第2款规定的新颖性。\n\n\(request.content)"),
            ("创造性分析", "分析以下技术方案的创造性，用三步法评估是否具备专利法第22条第3款规定的创造性。\n\n\(request.content)"),
            ("侵权判定", "基于以下技术方案，分析潜在侵权风险，判定是否落入已知专利的保护范围。\n\n\(request.content)"),
        ]

        _ = await subAgentEngine.spawnBatch(
            tasks: tasks,
            projectFolder: "",
            modelRouter: modelRouter,
            provider: provider
        )

        let completed = await subAgentEngine.waitAll(timeout: 300)
        let notifications = completed.map { $0.notification }

        state = .idle
        let summary = """
        专利三路并行分析完成 (共 \(completed.count) 路):

        \(notifications.joined(separator: "\n\n"))
        """
        return .completed(summary)
    }
}
