import Foundation

public final class TraceStore: @unchecked Sendable {
    private let tracesDir: URL
    public init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            ".yunpat/traces/\(formatter.string(from: Date()))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.tracesDir = dir
    }
    public func save(requestId: UUID, capabilities: [CapabilityTrace], prompts: [PromptTrace], summary: TraceSummary)
        async throws {
        let dict: [String: Any] = [
            "requestId": requestId.uuidString,
            "summary": [
                "totalCost": summary.totalCost, "totalLatency": summary.totalLatency, "toolCount": summary.toolCount,
                "llmCallCount": summary.llmCallCount
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
        try data.write(to: tracesDir.appendingPathComponent("req-\(requestId.uuidString.prefix(8)).json"))
    }
}
