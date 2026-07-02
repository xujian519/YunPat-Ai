import Foundation

/// Persists CaseContext, LongTermMemory, and GlobalMemory via UserDefaults.
/// WorkingMemory and SessionFacts are ephemeral — never stored here.
public actor MemoryStore {
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - CaseContext (Layer 3)

    public func saveCaseContext(_ context: CaseContext) throws {
        let data = try encoder.encode(context)
        defaults.set(data, forKey: "yunpat.memory.case.\(context.caseId)")
    }

    public func loadCaseContext(_ caseId: String) -> CaseContext? {
        guard let data = defaults.data(forKey: "yunpat.memory.case.\(caseId)") else {
            return nil
        }
        return try? decoder.decode(CaseContext.self, from: data)
    }

    public func removeCaseContext(_ caseId: String) {
        defaults.removeObject(forKey: "yunpat.memory.case.\(caseId)")
    }

    // MARK: - LongTermMemory (Layer 4)

    public func saveLongTermMemory(_ memory: LongTermMemory) throws {
        let data = try encoder.encode(memory)
        defaults.set(data, forKey: "yunpat.memory.longterm")
    }

    public func loadLongTermMemory() -> LongTermMemory {
        guard let data = defaults.data(forKey: "yunpat.memory.longterm") else {
            return LongTermMemory()
        }
        return (try? decoder.decode(LongTermMemory.self, from: data)) ?? LongTermMemory()
    }

    // MARK: - GlobalMemory (Layer 5)

    public func saveGlobalMemory(_ global: GlobalMemory) throws {
        let data = try encoder.encode(global)
        defaults.set(data, forKey: "yunpat.memory.global")
    }

    public func loadGlobalMemory() -> GlobalMemory {
        guard let raw = defaults.data(forKey: "yunpat.memory.global"),
            let decoded = try? decoder.decode(GlobalMemory.self, from: raw)
        else {
            return GlobalMemory()
        }
        return decoded
    }
}
