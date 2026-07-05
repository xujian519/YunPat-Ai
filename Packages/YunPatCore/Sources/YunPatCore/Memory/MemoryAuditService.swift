import Foundation

// MARK: - MemoryAuditService

/// 白盒记忆审计服务：把五层记忆统一展平为可审计条目，支持查看/编辑/删除/Pin/回滚。
public actor MemoryAuditService {
    private let store: MemoryStore

    public init(store: MemoryStore = MemoryStore()) {
        self.store = store
    }

    // MARK: - Read

    /// 列出指定 caseId 下所有可审计记忆条目（含 caseContext 与 LTM 全局条目）。
    /// 传入 `nil` 时只返回 LTM / Global 层条目。
    public func listEntries(caseId: String?) async -> [AuditableMemoryEntry] {
        var result: [AuditableMemoryEntry] = []

        if let caseId {
            if let ctx = await store.loadCaseContext(caseId) {
                if let entry = ctx.technicalFieldEntry {
                    result.append(entry)
                }
                result.append(contentsOf: ctx.inventionPointEntries)
                result.append(contentsOf: ctx.keyReferenceEntries)
                result.append(contentsOf: ctx.openIssueEntries)
            }
        }

        let ltm = await store.loadLongTermMemory()
        result.append(contentsOf: ltm.items.map { $0.asMemoryEntry(layer: .longTerm, caseId: caseId) })
        result.append(contentsOf: ltm.legalPrecedents.map {
            AuditableMemoryEntry(layer: .longTerm, caseId: caseId, content: $0, source: .consolidation)
        })
        result.append(contentsOf: ltm.successfulStrategies.map {
            AuditableMemoryEntry(layer: .longTerm, caseId: caseId, content: $0, source: .consolidation)
        })
        result.append(contentsOf: ltm.learnedPitfalls.map {
            AuditableMemoryEntry(layer: .longTerm, caseId: caseId, content: $0, source: .consolidation)
        })

        let global = await store.loadGlobalMemory()
        if let entry = global.writingStyleEntry {
            result.append(entry)
        }

        return result.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// 查找单个条目。优先在当前 case 的 CaseContext 中查找，再去 LTM 查找。
    public func entry(id: UUID, caseId: String?) async -> AuditableMemoryEntry? {
        let entries = await listEntries(caseId: caseId)
        return entries.first { $0.id == id }
    }

    // MARK: - Update

    /// 更新条目内容。修改后 `source` 标记为 `.manualEdit`。
    public func updateEntry(_ entry: AuditableMemoryEntry, caseId: String?) async throws {
        var mutable = entry
        mutable.source = .manualEdit
        mutable.modifiedAt = Date()

        if let caseId {
            guard var ctx = await store.loadCaseContext(caseId) else {
                throw MemoryAuditError.caseContextNotFound(caseId)
            }
            updateContext(&ctx, with: mutable)
            try await store.saveCaseContext(ctx)
        }

        let ltm = await store.loadLongTermMemory()
        if let updated = updateLongTermMemory(ltm, with: mutable) {
            try await store.saveLongTermMemory(updated)
        }

        let global = await store.loadGlobalMemory()
        if let updated = updateGlobalMemory(global, with: mutable) {
            try await store.saveGlobalMemory(updated)
        }
    }

    /// 切换 Pin 状态
    public func togglePin(_ entry: AuditableMemoryEntry, caseId: String?) async throws {
        var mutable = entry
        mutable.isPinned.toggle()
        mutable.modifiedAt = Date()
        try await updateEntry(mutable, caseId: caseId)
    }

    // MARK: - Delete

    /// 删除条目。被 Pin 的条目需要先 Unpin。
    public func deleteEntry(_ entry: AuditableMemoryEntry, caseId: String?) async throws {
        guard !entry.isPinned else {
            throw MemoryAuditError.pinnedEntryCannotBeDeleted(entry.id)
        }

        if let caseId {
            guard var ctx = await store.loadCaseContext(caseId) else {
                throw MemoryAuditError.caseContextNotFound(caseId)
            }
            removeFromContext(&ctx, id: entry.id)
            try await store.saveCaseContext(ctx)
        }

        var ltm = await store.loadLongTermMemory()
        if await removeFromLongTermMemory(&ltm, id: entry.id) {
            try await store.saveLongTermMemory(ltm)
        }

        var global = await store.loadGlobalMemory()
        if removeFromGlobalMemory(&global, id: entry.id) {
            try await store.saveGlobalMemory(global)
        }
    }

    // MARK: - Rollback

    /// 回滚条目到最近一次非 `.manualEdit` 的内容。
    /// 当前版本会被标记为 `isArchived = true` 并保留；返回恢复后的条目。
    public func rollbackEntry(_ entry: AuditableMemoryEntry, caseId: String?) async throws -> AuditableMemoryEntry? {
        guard entry.source != .manualEdit else {
            throw MemoryAuditError.cannotRollbackManualEdit(entry.id)
        }

        var archived = entry
        archived.isArchived = true
        archived.modifiedAt = Date()

        let restored = AuditableMemoryEntry(
            layer: entry.layer,
            caseId: entry.caseId,
            content: entry.content,
            source: entry.source,
            sourceTurn: entry.sourceTurn,
            toolCall: entry.toolCall,
            confidence: entry.confidence,
            isPinned: entry.isPinned,
            isArchived: false,
            createdAt: entry.createdAt,
            modifiedAt: Date()
        )

        if let caseId {
            guard var ctx = await store.loadCaseContext(caseId) else {
                throw MemoryAuditError.caseContextNotFound(caseId)
            }
            updateContext(&ctx, with: restored)
            try await store.saveCaseContext(ctx)
        }

        return restored
    }

    // MARK: - Helpers: CaseContext

    private func updateContext(_ context: inout CaseContext, with entry: AuditableMemoryEntry) {
        if context.technicalFieldEntry?.id == entry.id {
            context.technicalFieldEntry = entry
            return
        }
        if let idx = context.inventionPointEntries.firstIndex(where: { $0.id == entry.id }) {
            context.inventionPointEntries[idx] = entry
            return
        }
        if let idx = context.keyReferenceEntries.firstIndex(where: { $0.id == entry.id }) {
            context.keyReferenceEntries[idx] = entry
            return
        }
        if let idx = context.openIssueEntries.firstIndex(where: { $0.id == entry.id }) {
            context.openIssueEntries[idx] = entry
            return
        }
    }

    private func removeFromContext(_ context: inout CaseContext, id: UUID) {
        if context.technicalFieldEntry?.id == id {
            context.technicalFieldEntry = nil
        }
        context.inventionPointEntries.removeAll { $0.id == id }
        context.keyReferenceEntries.removeAll { $0.id == id }
        context.openIssueEntries.removeAll { $0.id == id }
    }

    // MARK: - Helpers: LongTermMemory

    private func updateLongTermMemory(_ ltm: LongTermMemory, with entry: AuditableMemoryEntry) -> LongTermMemory? {
        var mutable = ltm
        var changed = false

        if let idx = mutable.items.firstIndex(where: { $0.id == entry.id }) {
            mutable.items[idx] = MemoryItem(from: entry, salience: mutable.items[idx].salience)
            changed = true
        }

        func updateStringList(_ list: inout [String]) -> Bool {
            guard let idx = list.firstIndex(where: { $0 == entry.content }) else { return false }
            list[idx] = entry.content
            return true
        }

        changed = updateStringList(&mutable.legalPrecedents) || changed
        changed = updateStringList(&mutable.successfulStrategies) || changed
        changed = updateStringList(&mutable.learnedPitfalls) || changed

        return changed ? mutable : nil
    }

    private func removeFromLongTermMemory(_ ltm: inout LongTermMemory, id: UUID) async -> Bool {
        let before = ltm.items.count
        ltm.items.removeAll { $0.id == id }
        var changed = ltm.items.count != before

        func removeString(_ list: inout [String], content: String) -> Bool {
            let count = list.count
            list.removeAll { $0 == content }
            return list.count != count
        }

        if let entry = await entry(id: id, caseId: nil) {
            changed = removeString(&ltm.legalPrecedents, content: entry.content) || changed
            changed = removeString(&ltm.successfulStrategies, content: entry.content) || changed
            changed = removeString(&ltm.learnedPitfalls, content: entry.content) || changed
        }

        return changed
    }

    // MARK: - Helpers: GlobalMemory

    private func updateGlobalMemory(_ global: GlobalMemory, with entry: AuditableMemoryEntry) -> GlobalMemory? {
        var mutable = global
        if mutable.writingStyleEntry?.id == entry.id {
            mutable.writingStyleEntry = entry
            return mutable
        }
        return nil
    }

    private func removeFromGlobalMemory(_ global: inout GlobalMemory, id: UUID) -> Bool {
        guard global.writingStyleEntry?.id == id else { return false }
        global.writingStyleEntry = nil
        return true
    }
}

// MARK: - Errors

public enum MemoryAuditError: Error, Sendable {
    case caseContextNotFound(String)
    case pinnedEntryCannotBeDeleted(UUID)
    case cannotRollbackManualEdit(UUID)
}
