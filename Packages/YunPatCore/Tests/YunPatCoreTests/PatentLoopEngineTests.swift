import XCTest
import YunPatNetworking
@testable import YunPatCore

// MARK: - Local mock backend (MockModelBackend is in YunPatNetworking test target, not accessible here)
private final class TestMockBackend: ModelBackend {
    let provider: ModelProvider = .openai
    let mockResponse: String

    init(mockResponse: String) { self.mockResponse = mockResponse }

    var rateLimit: RateLimitInfo? { get async { nil } }

    func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            for char in self.mockResponse {
                continuation.yield(.text(String(char)))
            }
            continuation.yield(.finish(reason: .stop, usage: nil))
            continuation.finish()
        }
    }

    func listModels() async throws -> [ModelInfo] { [] }
    func capabilities() -> ModelCapabilities { ModelCapabilities() }
    func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy { .fail }
}

final class PatentLoopEngineTests: XCTestCase {
    func prepareTempVault() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("Wiki/专利实务"), withIntermediateDirectories: true)
        try? "[[创造性-概述]]".write(to: dir.appendingPathComponent("Wiki/专利实务/index.md"), atomically: true, encoding: .utf8)
        try? "# 创造性概述\n三步法是判断发明创造性的法定框架。".write(to: dir.appendingPathComponent("Wiki/创造性-概述.md"), atomically: true, encoding: .utf8)
        return dir
    }

    func testRun_fullAgent_withMock_returnsCompleted() async throws {
        let vaultURL = prepareTempVault()
        let adapter = WikiAdapter(vaultPath: vaultURL)
        let router = ModelRouter()
        let mock = TestMockBackend(mockResponse: "分析完成：该机构具备创造性。")
        await router.register(mock)
        let engine = PatentLoopEngine(modelRouter: router, wikiAdapter: adapter, provider: .openai, config: LoopConfig(maxRevisionCycles: 1))
        let result = try await engine.run(request: UserRequest(content: "分析螺旋传动机构的创造性"), flow: .fullAgent)
        switch result {
        case .completed(let text): XCTAssertTrue(text.contains("创造"))
        case .exceededRevisionLimit: break
        default: XCTFail("Expected .completed or .exceededRevisionLimit")
        }
    }
}
