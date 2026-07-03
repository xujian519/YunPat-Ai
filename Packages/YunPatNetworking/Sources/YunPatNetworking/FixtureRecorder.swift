import Foundation

/// Fixture 录制/回放命名空间
public enum FixtureRecorder {}

// MARK: - HTTPFixtureRecorder

/// 录制器 — 包装真实 ModelBackend，拦截每次 chat() 调用的请求与响应 chunk 序列
///
/// 用法：
/// 1. 用真实 provider 构造 Recorder：`let recorder = HTTPFixtureRecorder(wrapping: OpenAIProvider(...))`
/// 2. 注册到 ModelRouter，正常跑测试场景
/// 3. 调用 `exportFixture()` 或 `saveFixture(to:)` 导出 JSON
///
/// 线程安全：final class + NSLock 保护 records，标注 @unchecked Sendable。
public final class HTTPFixtureRecorder: ModelBackend, @unchecked Sendable {

    public let provider: ModelProvider
    private let wrapped: ModelBackend
    private var records: [FixtureRecord] = []
    private let lock: NSLock = NSLock()

    public init(wrapping backend: ModelBackend) {
        self.wrapped = backend
        self.provider = backend.provider
    }

    public var rateLimit: RateLimitInfo? { get async { await wrapped.rateLimit } }

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        let rawStream: AsyncThrowingStream<ChatChunk, Error> = wrapped.chat(request)
        let reqModel: String = request.model
        let reqCount: Int = request.messages.count

        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                var collected: [FixtureChunk] = []
                do {
                    for try await chunk in rawStream {
                        collected.append(FixtureChunk(from: chunk))
                        continuation.yield(chunk)
                    }
                    self?.appendRecord(model: reqModel, count: reqCount, chunks: collected)
                    continuation.finish()
                } catch {
                    collected.append(.error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
                    self?.appendRecord(model: reqModel, count: reqCount, chunks: collected)
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func listModels() async throws -> [ModelInfo] { try await wrapped.listModels() }
    public func capabilities() -> ModelCapabilities { wrapped.capabilities() }
    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy {
        await wrapped.onRateLimitExceeded(error)
    }

    // MARK: - 导出

    private func appendRecord(model: String, count: Int, chunks: [FixtureChunk]) {
        lock.withLock {
            records.append(FixtureRecord(requestModel: model, requestMessageCount: count, chunks: chunks))
        }
    }

    /// 导出录制为 FixtureDocument
    public func exportFixture() -> FixtureDocument {
        lock.withLock { FixtureDocument(provider: provider.rawValue, records: records) }
    }

    /// 保存录制到 JSON 文件
    public func saveFixture(to url: URL) throws {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data = try encoder.encode(exportFixture())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// 已录制的调用次数
    public var recordedCallCount: Int { lock.withLock { records.count } }
}

// MARK: - ReplayModelBackend

/// 回放器 — 从 FixtureDocument 顺序回放 chunk 序列，模拟真实 Provider 行为（含 usage）
///
/// 用法：
/// ```swift
/// let replay = try ReplayModelBackend(provider: .deepseek, fixtureURL: url)
/// await router.register(replay)
/// // 之后的所有 chat() 调用走 fixture 回放，不联网
/// ```
///
/// 匹配策略：**顺序匹配** — 第 N 次 chat() 回放第 N 条 record。
/// 适合确定性测试场景。调用次数超过录制次数时抛 FixtureExhaustedError。
public final class ReplayModelBackend: ModelBackend, @unchecked Sendable {

    public let provider: ModelProvider
    private let records: [FixtureRecord]
    private var callIndex: Int = 0
    private let lock: NSLock = NSLock()

    public init(provider: ModelProvider, fixture: FixtureDocument) {
        self.provider = provider
        self.records = fixture.records
    }

    public init(provider: ModelProvider, fixtureURL: URL) throws {
        self.provider = provider
        let data: Data = try Data(contentsOf: fixtureURL)
        let doc: FixtureDocument = try JSONDecoder().decode(FixtureDocument.self, from: data)
        self.records = doc.records
    }

    /// 从内联 JSON 字符串构造（测试便捷用）
    public init(provider: ModelProvider, jsonString: String) throws {
        self.provider = provider
        guard let data = jsonString.data(using: .utf8) else {
            throw FixtureReplayError(message: "Invalid JSON string encoding")
        }
        let doc: FixtureDocument = try JSONDecoder().decode(FixtureDocument.self, from: data)
        self.records = doc.records
    }

    public var rateLimit: RateLimitInfo? { get async { nil } }

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            let idx: Int = self.lock.withLock { () -> Int in
                let current: Int = self.callIndex
                self.callIndex += 1
                return current
            }
            guard idx < self.records.count else {
                continuation.finish(
                    throwing: FixtureExhaustedError(
                        requestsMade: idx, requestsRecorded: self.records.count))
                return
            }
            for fixtureChunk in self.records[idx].chunks {
                continuation.yield(fixtureChunk.toChatChunk())
            }
            continuation.finish()
        }
    }

    public func listModels() async throws -> [ModelInfo] { [] }
    public func capabilities() -> ModelCapabilities { ModelCapabilities() }
    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy { .fail }

    /// 重置回放指针（可在多次测试间复用同一实例）
    public func reset() {
        lock.withLock { callIndex = 0 }
    }
}
