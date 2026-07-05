import Foundation

// MARK: - TokenUsageRecord

/// 单次 LLM 调用 token/cost 记录
public struct TokenUsageRecord: Identifiable, Sendable, Codable {
    public let id: UUID
    public let caseId: String?
    public let provider: String
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let costUsd: Double
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        caseId: String?,
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        costUsd: Double,
        timestamp: Date
    ) {
        self.id = id
        self.caseId = caseId
        self.provider = provider
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUsd = costUsd
        self.timestamp = timestamp
    }

    public var totalTokens: Int { inputTokens + outputTokens }
}

// MARK: - TokenUsageStore

/// Token 使用记录持久化存储
public actor TokenUsageStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// 追加一条记录
    public func append(_ record: TokenUsageRecord) async throws {
        var records: [TokenUsageRecord] = (try? await loadAll()) ?? []
        records.append(record)
        try await saveAll(records)
    }

    /// 加载全部记录
    public func loadAll() async throws -> [TokenUsageRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data: Data = try Data(contentsOf: fileURL)
        return try decoder.decode([TokenUsageRecord].self, from: data)
    }

    /// 按 caseId 过滤记录
    public func loadForCase(caseId: String) async throws -> [TokenUsageRecord] {
        try await loadAll().filter { $0.caseId == caseId }
    }

    /// 保存全部记录
    public func saveAll(_ records: [TokenUsageRecord]) async throws {
        let dir: URL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data: Data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }

    /// 清空记录
    public func removeAll() async throws {
        try Data().write(to: fileURL, options: .atomic)
    }

    /// 默认存储路径 `~/.yunpat/token-usage.json`
    public static func defaultFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".yunpat/token-usage.json")
    }
}
