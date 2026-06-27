import Foundation

public struct TraceID: Sendable, Hashable { public let id: UUID; public init() { id = UUID() } }

public struct CapabilityTrace: Sendable, Codable {
    public let capability: String; public let tool: String; public let latency: TimeInterval; public let error: String?
    public init(capability: String, tool: String, latency: TimeInterval, error: String? = nil) { self.capability = capability; self.tool = tool; self.latency = latency; self.error = error }
}

public struct PromptTrace: Sendable, Codable {
    public let systemPromptHash: String; public let cost: Double; public let latency: TimeInterval; public let model: String
    public init(systemPromptHash: String, cost: Double, latency: TimeInterval, model: String) { self.systemPromptHash = systemPromptHash; self.cost = cost; self.latency = latency; self.model = model }
}

public struct TraceSummary: Sendable, Codable {
    public let totalCost: Double; public let totalLatency: TimeInterval; public let toolCount: Int; public let llmCallCount: Int
    public init(totalCost: Double, totalLatency: TimeInterval, toolCount: Int, llmCallCount: Int) { self.totalCost = totalCost; self.totalLatency = totalLatency; self.toolCount = toolCount; self.llmCallCount = llmCallCount }
}

public actor TraceCollector {
    private var traces: [TraceID: (capabilities: [CapabilityTrace], prompts: [PromptTrace])] = [:]
    private let store = TraceStore()
    public func startTrace() -> TraceID { let id = TraceID(); traces[id] = ([], []); return id }
    public func recordCapability(_ trace: CapabilityTrace, parent: TraceID) { traces[parent]?.capabilities.append(trace) }
    public func recordPrompt(_ trace: PromptTrace, parent: TraceID) { traces[parent]?.prompts.append(trace) }
    public func finishTrace(_ id: TraceID, summary: TraceSummary) async throws { guard let entry = traces[id] else { return }; try await store.save(requestId: id.id, capabilities: entry.capabilities, prompts: entry.prompts, summary: summary); traces[id] = nil }
}
