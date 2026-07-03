import Foundation

/// 五层记忆引擎 — 协调 Working / Session / Case / LongTerm / Global 五层记忆
///
/// Layers (shortest → longest lifetime):
///   1. WorkingMemory  — single loop iteration, never persisted
///   2. SessionFact     — current session, ephemeral facts
///   3. CaseContext     — per-patent-case, persisted via MemoryStore
///   4. LongTermMemory  — cross-case knowledge, persisted via MemoryStore
///   5. GlobalMemory    — user preferences, persisted via MemoryStore
///
/// 集成 MemoryWritePath / MemoryReadPath / MemoryConsolidator 三个工程化模块：
/// - SessionFact（文本）仍直接 append 到 sessionFacts 数组（ephmeral，不持久化）
/// - 对话轮次通过 MemoryWritePath.bufferTurn() 缓冲 → 60s 防抖 → LLM 蒸馏 → 写回 store
/// - CaseContext 检索通过 MemoryReadPath 做 relevance gate
/// - LTM 维护通过 MemoryConsolidator.run() 做 decay/promote/evict/prune
public actor MemoryEngine {
    private let store: MemoryStore
    public let writePath: MemoryWritePath
    public let readPath: MemoryReadPath
    public let consolidator: MemoryConsolidator
    private var working: WorkingMemory
    private var sessionFacts: [SessionFact]

    public init(
        store: MemoryStore = MemoryStore(),
        writePath: MemoryWritePath = MemoryWritePath(),
        readPath: MemoryReadPath = MemoryReadPath(),
        consolidator: MemoryConsolidator = MemoryConsolidator()
    ) {
        self.store = store
        self.writePath = writePath
        self.readPath = readPath
        self.consolidator = consolidator
        self.working = WorkingMemory()
        self.sessionFacts = []
    }

    // MARK: - Layer 1: WorkingMemory

    /// 设置当前工作目标
    public func setGoal(_ goal: String) {
        working.currentGoal = goal
    }

    /// 获取当前工作目标
    public func currentGoal() -> String {
        working.currentGoal
    }

    /// 添加一条活跃假设
    public func addHypothesis(_ hypothesis: String) {
        working.activeHypotheses.append(hypothesis)
    }

    /// 获取所有活跃假设
    public func activeHypotheses() -> [String] {
        working.activeHypotheses
    }

    /// 向草稿板添加一条记录
    public func noteToScratchpad(_ note: String) {
        working.scratchpad.append(note)
    }

    /// 获取草稿板所有记录
    public func scratchpad() -> [String] {
        working.scratchpad
    }

    /// 设置中间结果
    public func setResult(_ value: String, forKey key: String) {
        working.intermediateResults[key] = value
    }

    /// 获取指定 key 的中间结果
    public func result(forKey key: String) -> String? {
        working.intermediateResults[key]
    }

    /// 清空 WorkingMemory（两个循环迭代之间调用）
    public func resetWorkingMemory() {
        working = WorkingMemory()
    }

    // MARK: - Layer 2: SessionFacts

    /// 添加一条 SessionFact
    public func addSessionFact(_ fact: SessionFact) {
        sessionFacts.append(fact)
    }

    /// 添加一条文本类型的 SessionFact，指定分类
    public func addSessionFact(_ text: String, category: FactCategory = .other) {
        sessionFacts.append(SessionFact(fact: text, category: category))
    }

    /// 添加对话轮次到 WritePath 缓冲区（通过 bufferTurn + 60s 防抖蒸馏）
    ///
    /// 热路径：仅做轻量存储 + 防抖 arm，无 LLM 调用。
    /// 当 60s 无新信号或显式调用 flush 时触发 LLM 蒸馏写入 CaseContext。
    /// - Parameters:
    ///   - user: 用户消息
    ///   - assistant: 助手回复
    ///   - caseId: 关联案件 ID
    public func addSessionFact(user: String, assistant: String, caseId: String) async {
        await writePath.bufferTurn(user: user, assistant: assistant, caseId: caseId)
    }

    /// 强制立即刷新 WritePath 缓冲区（session 切换 / 用户手动保存时调用）
    public func flushWritePath(caseId: String) async {
        await writePath.flush(caseId: caseId)
    }

    /// 恢复 WritePath 中崩溃时未处理的信号
    public func recoverWritePathSignals() async {
        await writePath.recoverOrphanedSignals()
    }

    /// 获取所有待处理的 SessionFact
    public func pendingSessionFacts() -> [SessionFact] {
        sessionFacts
    }

    /// 获取指定分类的 SessionFact
    public func sessionFacts(ofCategory category: FactCategory) -> [SessionFact] {
        sessionFacts.filter { $0.category == category }
    }

    // MARK: - Layer 3: CaseContext

    /// 保存 CaseContext 到持久化存储
    /// - Note: 写操作经过 MemoryWritePath 协调，数据最终写入 MemoryStore
    public func saveCaseContext(_ context: CaseContext) async throws {
        // 先 flush WritePath 缓冲，确保待蒸馏信号已处理
        await writePath.flush(caseId: context.caseId)
        try await store.saveCaseContext(context)
    }

    /// 从持久化存储加载 CaseContext（完整加载，未经过相关性门控）
    public func loadCaseContext(_ caseId: String) async -> CaseContext? {
        await store.loadCaseContext(caseId)
    }

    /// 通过 MemoryReadPath 执行相关性门控检索，返回装配后的记忆块
    /// - Parameters:
    ///   - caseId: 案件 ID
    ///   - query: 当前用户查询，用于相关性过滤
    /// - Returns: 过滤后的记忆块，无相关记忆时返回 nil
    public func loadCaseContext(caseId: String, query: String) async -> MemoryBlock? {
        await readPath.assemble(for: query, caseId: caseId)
    }

    /// 移除指定 CaseContext
    public func removeCaseContext(_ caseId: String) async {
        await store.removeCaseContext(caseId)
    }

    // MARK: - Layer 4: LongTermMemory

    /// 加载 LongTermMemory（跨案件知识）
    public func loadLongTermMemory() async -> LongTermMemory {
        await store.loadLongTermMemory()
    }

    /// 保存 LongTermMemory 到持久化存储
    public func saveLongTermMemory(_ memory: LongTermMemory) async throws {
        try await store.saveLongTermMemory(memory)
    }

    /// 添加法理先例到 LongTermMemory（自动去重）
    public func addLegalPrecedent(_ precedent: String) async throws {
        var ltm = await store.loadLongTermMemory()
        if !ltm.legalPrecedents.contains(precedent) {
            ltm.legalPrecedents.append(precedent)
            ltm.lastConsolidated = Date()
            try await store.saveLongTermMemory(ltm)
        }
    }

    /// 添加成功策略到 LongTermMemory（自动去重）
    public func addSuccessfulStrategy(_ strategy: String) async throws {
        var ltm = await store.loadLongTermMemory()
        if !ltm.successfulStrategies.contains(strategy) {
            ltm.successfulStrategies.append(strategy)
            ltm.lastConsolidated = Date()
            try await store.saveLongTermMemory(ltm)
        }
    }

    /// 添加已学教训到 LongTermMemory（自动去重）
    public func addPitfall(_ pitfall: String) async throws {
        var ltm = await store.loadLongTermMemory()
        if !ltm.learnedPitfalls.contains(pitfall) {
            ltm.learnedPitfalls.append(pitfall)
            ltm.lastConsolidated = Date()
            try await store.saveLongTermMemory(ltm)
        }
    }

    // MARK: - Layer 5: GlobalMemory

    /// 加载 GlobalMemory（用户偏好等跨 session 数据）
    public func loadGlobalMemory() async -> GlobalMemory {
        await store.loadGlobalMemory()
    }

    /// 保存 GlobalMemory 到持久化存储
    public func saveGlobalMemory(_ global: GlobalMemory) async throws {
        try await store.saveGlobalMemory(global)
    }

    // MARK: - Consolidation

    /// Promote session facts into a CaseContext, clear session facts.
    ///
    /// 集成 MemoryWritePath.flush + MemoryConsolidator.run：
    ///   1. 先 flush WritePath 确保待蒸馏对话已处理
    ///   2. 从 sessionFacts 构建 CaseContext
    ///   3. 持久化 CaseContext 到 MemoryStore
    ///   4. 清空 sessionFacts
    ///   5. 委托 MemoryConsolidator 执行 LTM 维护（decay/promote/evict）
    public func consolidate() async throws -> CaseContext {
        let ctx = buildCaseContext()
        // 先 flush WritePath 缓冲
        await writePath.flush(caseId: ctx.caseId)
        try await store.saveCaseContext(ctx)
        sessionFacts.removeAll()
        // 委托 MemoryConsolidator 执行 LTM 维护
        if await consolidator.shouldRun {
            await consolidator.run()
        }
        return ctx
    }

    /// Full consolidation: promote session facts to CaseContext,
    /// and persist strategy-level facts to LongTermMemory.
    ///
    /// 集成 MemoryWritePath.flush + MemoryConsolidator.run：
    ///   1. 先 flush WritePath 确保待蒸馏对话已处理
    ///   2. 从 sessionFacts 构建 CaseContext 并持久化
    ///   3. 抽取 strategy 分类的事实提升到 LongTermMemory
    ///   4. 清空 sessionFacts
    ///   5. 委托 MemoryConsolidator 执行 LTM 维护（decay/promote/evict/prune）
    public func consolidateDeep() async throws -> (CaseContext, LongTermMemory) {
        let ctx = buildCaseContext()
        // 先 flush WritePath 缓冲
        await writePath.flush(caseId: ctx.caseId)
        try await store.saveCaseContext(ctx)

        let strategies = sessionFacts(ofCategory: .strategy).map(\.fact)
        sessionFacts.removeAll()

        var ltm = await store.loadLongTermMemory()
        for string in strategies where !ltm.successfulStrategies.contains(string) {
            ltm.successfulStrategies.append(string)
        }
        ltm.lastConsolidated = Date()
        try await store.saveLongTermMemory(ltm)

        // 委托 MemoryConsolidator 执行 LTM 维护
        if await consolidator.shouldRun {
            await consolidator.run()
        }
        return (ctx, ltm)
    }

    // MARK: - Helpers

    private func buildCaseContext() -> CaseContext {
        let techField = sessionFacts(ofCategory: .technicalFeature).first?.fact ?? ""
        let inventionPoints = sessionFacts(ofCategory: .technicalFeature).map(\.fact)
        let keyRefs =
            sessionFacts
            .filter { $0.category == .legalRule || $0.category == .decision }
            .map(\.fact)
        return CaseContext(
            caseId: "active",
            technicalField: techField,
            inventionPoints: inventionPoints,
            keyReferences: keyRefs
        )
    }
}
