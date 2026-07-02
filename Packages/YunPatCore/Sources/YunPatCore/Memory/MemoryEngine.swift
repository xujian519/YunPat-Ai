import Foundation

/// 5-layer memory engine coordinating all memory tiers.
///
/// Layers (shortest → longest lifetime):
///   1. WorkingMemory  — single loop iteration, never persisted
///   2. SessionFact     — current session, ephemeral facts
///   3. CaseContext     — per-patent-case, persisted via MemoryStore
///   4. LongTermMemory  — cross-case knowledge, persisted via MemoryStore
///   5. GlobalMemory    — user preferences, persisted via MemoryStore
public actor MemoryEngine {
    private let store: MemoryStore
    private var working: WorkingMemory
    private var sessionFacts: [SessionFact]

    public init(store: MemoryStore = MemoryStore()) {
        self.store = store
        self.working = WorkingMemory()
        self.sessionFacts = []
    }

    // MARK: - Layer 1: WorkingMemory

    public func setGoal(_ goal: String) {
        working.currentGoal = goal
    }

    public func currentGoal() -> String {
        working.currentGoal
    }

    public func addHypothesis(_ hypothesis: String) {
        working.activeHypotheses.append(hypothesis)
    }

    public func activeHypotheses() -> [String] {
        working.activeHypotheses
    }

    public func noteToScratchpad(_ note: String) {
        working.scratchpad.append(note)
    }

    public func scratchpad() -> [String] {
        working.scratchpad
    }

    public func setResult(_ value: String, forKey key: String) {
        working.intermediateResults[key] = value
    }

    public func result(forKey key: String) -> String? {
        working.intermediateResults[key]
    }

    /// Clear working memory between loop iterations.
    public func resetWorkingMemory() {
        working = WorkingMemory()
    }

    // MARK: - Layer 2: SessionFacts

    public func addSessionFact(_ fact: SessionFact) {
        sessionFacts.append(fact)
    }

    public func addSessionFact(_ text: String, category: FactCategory = .other) {
        sessionFacts.append(SessionFact(fact: text, category: category))
    }

    public func pendingSessionFacts() -> [SessionFact] {
        sessionFacts
    }

    public func sessionFacts(ofCategory category: FactCategory) -> [SessionFact] {
        sessionFacts.filter { $0.category == category }
    }

    // MARK: - Layer 3: CaseContext

    public func saveCaseContext(_ context: CaseContext) async throws {
        try await store.saveCaseContext(context)
    }

    public func loadCaseContext(_ caseId: String) async -> CaseContext? {
        await store.loadCaseContext(caseId)
    }

    public func removeCaseContext(_ caseId: String) async {
        await store.removeCaseContext(caseId)
    }

    // MARK: - Layer 4: LongTermMemory

    public func loadLongTermMemory() async -> LongTermMemory {
        await store.loadLongTermMemory()
    }

    public func saveLongTermMemory(_ memory: LongTermMemory) async throws {
        try await store.saveLongTermMemory(memory)
    }

    public func addLegalPrecedent(_ precedent: String) async throws {
        var ltm = await store.loadLongTermMemory()
        if !ltm.legalPrecedents.contains(precedent) {
            ltm.legalPrecedents.append(precedent)
            ltm.lastConsolidated = Date()
            try await store.saveLongTermMemory(ltm)
        }
    }

    public func addSuccessfulStrategy(_ strategy: String) async throws {
        var ltm = await store.loadLongTermMemory()
        if !ltm.successfulStrategies.contains(strategy) {
            ltm.successfulStrategies.append(strategy)
            ltm.lastConsolidated = Date()
            try await store.saveLongTermMemory(ltm)
        }
    }

    public func addPitfall(_ pitfall: String) async throws {
        var ltm = await store.loadLongTermMemory()
        if !ltm.learnedPitfalls.contains(pitfall) {
            ltm.learnedPitfalls.append(pitfall)
            ltm.lastConsolidated = Date()
            try await store.saveLongTermMemory(ltm)
        }
    }

    // MARK: - Layer 5: GlobalMemory

    public func loadGlobalMemory() async -> GlobalMemory {
        await store.loadGlobalMemory()
    }

    public func saveGlobalMemory(_ global: GlobalMemory) async throws {
        try await store.saveGlobalMemory(global)
    }

    // MARK: - Consolidation

    /// Promote session facts into a CaseContext, clear session facts.
    public func consolidate() async throws -> CaseContext {
        let techField = sessionFacts(ofCategory: .technicalFeature).first?.fact ?? ""
        let inventionPoints = sessionFacts(ofCategory: .technicalFeature).map(\.fact)
        let keyRefs =
            sessionFacts
            .filter { $0.category == .legalRule || $0.category == .decision }
            .map(\.fact)

        let ctx = CaseContext(
            caseId: "active",
            technicalField: techField,
            inventionPoints: inventionPoints,
            keyReferences: keyRefs
        )
        try await store.saveCaseContext(ctx)
        sessionFacts.removeAll()
        return ctx
    }

    /// Full consolidation: promote session facts to CaseContext,
    /// and persist strategy-level facts to LongTermMemory.
    public func consolidateDeep() async throws -> (CaseContext, LongTermMemory) {
        let techField = sessionFacts(ofCategory: .technicalFeature).first?.fact ?? ""
        let inventionPoints = sessionFacts(ofCategory: .technicalFeature).map(\.fact)
        let keyRefs =
            sessionFacts
            .filter { $0.category == .legalRule || $0.category == .decision }
            .map(\.fact)
        let strategies = sessionFacts(ofCategory: .strategy).map(\.fact)

        let ctx = CaseContext(
            caseId: "active",
            technicalField: techField,
            inventionPoints: inventionPoints,
            keyReferences: keyRefs
        )
        try await store.saveCaseContext(ctx)
        sessionFacts.removeAll()

        var ltm = await store.loadLongTermMemory()
        for string in strategies where !ltm.successfulStrategies.contains(string) {
            ltm.successfulStrategies.append(string)
        }
        ltm.lastConsolidated = Date()
        try await store.saveLongTermMemory(ltm)
        return (ctx, ltm)
    }
}
