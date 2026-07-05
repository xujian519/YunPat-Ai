import Testing
import YunPatNetworking
@testable import YunPatCore

struct RoutingEngineTests {

    @Test
    func classify_draftingKeywords() {
        #expect(RoutingEngine.classify("请帮我撰写独立权利要求") == .drafting)
        #expect(RoutingEngine.classify("说明书起草") == .drafting)
    }

    @Test
    func classify_retrievalKeywords() {
        #expect(RoutingEngine.classify("检索相关专利") == .retrieval)
        #expect(RoutingEngine.classify("查询法律状态") == .retrieval)
    }

    @Test
    func classify_analysisKeywords() {
        #expect(RoutingEngine.classify("分析创造性") == .analysis)
        #expect(RoutingEngine.classify("新颖性对比") == .analysis)
    }

    @Test
    func classify_summaryKeywords() {
        #expect(RoutingEngine.classify("总结这段内容") == .summary)
        #expect(RoutingEngine.classify("摘要概括") == .summary)
    }

    @Test
    func classify_generalFallback() {
        #expect(RoutingEngine.classify("随便聊聊") == .general)
    }

    @Test
    func route_balanced_defaultProvider() async {
        let engine: RoutingEngine = RoutingEngine()
        let request: RoutingRequest = RoutingRequest(content: "撰写权利要求")
        let decision: RoutingDecision = await engine.route(request)

        #expect(decision.provider == .deepseek)
        #expect(decision.model == "deepseek-reasoner")
        #expect(decision.estimatedInputTokens > 0)
        #expect(decision.estimatedCostUsd >= 0)
        #expect(!decision.reason.isEmpty)
    }

    @Test
    func route_cheapPrefersCheaperModel() async {
        let engine: RoutingEngine = RoutingEngine()
        let request: RoutingRequest = RoutingRequest(
            content: "总结这段专利摘要",
            constraints: RoutingConstraints(strategy: .cheap)
        )
        let decision: RoutingDecision = await engine.route(request)

        #expect(decision.estimatedCostUsd >= 0)
        #expect(decision.provider != .anthropic)
    }

    @Test
    func route_localOnly_whenNoLocalProvider() async {
        let engine: RoutingEngine = RoutingEngine()
        let request: RoutingRequest = RoutingRequest(
            content: "随便聊聊",
            constraints: RoutingConstraints(strategy: .localOnly)
        )
        let decision: RoutingDecision = await engine.route(request)

        #expect(ModelProvider.allLocal.contains(decision.provider))
    }

    @Test
    func route_preferredProvider_respected() async {
        let engine: RoutingEngine = RoutingEngine()
        let request: RoutingRequest = RoutingRequest(
            content: "分析侵权风险",
            constraints: RoutingConstraints(preferredProvider: .openai)
        )
        let decision: RoutingDecision = await engine.route(request)

        #expect(decision.provider == .openai)
        #expect(decision.model == "gpt-4o" || decision.model == "gpt-4o-mini")
    }

    @Test
    func route_caseBudgetDowngradesWhenExhausted() async {
        let config: TokenBudgetConfig = TokenBudgetConfig(
            globalMonthlyTokens: 1_000_000,
            perCaseTokens: 10,
            perRequestTokens: 50_000,
            globalMonthlyUsd: 50,
            perCaseUsd: 10
        )
        let service: TokenBudgetService = TokenBudgetService(config: config)
        let engine: RoutingEngine = RoutingEngine(budgetService: service)

        await service.recordUsage(
            caseId: "case-1",
            provider: .deepseek,
            model: "deepseek-reasoner",
            usage: Usage(promptTokens: 8, completionTokens: 2, totalTokens: 10)
        )

        let request: RoutingRequest = RoutingRequest(
            content: "撰写权利要求",
            caseId: "case-1",
            constraints: RoutingConstraints(strategy: .caseBudget)
        )
        let decision: RoutingDecision = await engine.route(request)

        // 预算接近耗尽，应降级到更便宜模型
        #expect(decision.model != "deepseek-reasoner" || decision.estimatedCostUsd == 0)
    }

    @Test
    func reportUsage_updatesBudget() async {
        let engine: RoutingEngine = RoutingEngine()
        let usage: Usage = Usage(promptTokens: 100, completionTokens: 50, totalTokens: 150)
        await engine.reportUsage(
            caseId: "case-a",
            provider: .deepseek,
            model: "deepseek-chat",
            usage: usage
        )

        _ = await engine.route(RoutingRequest(content: "测试", caseId: "case-a"))
        let snap: TokenBudgetSnapshot = await engine.snapshot(caseId: "case-a")
        #expect(snap.usedTokens == 150)
    }
}
