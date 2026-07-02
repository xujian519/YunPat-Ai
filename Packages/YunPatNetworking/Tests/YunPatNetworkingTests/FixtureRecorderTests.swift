import XCTest
import YunPatNetworking

final class FixtureRecorderTests: XCTestCase {

    // MARK: - 往返：录制 → 回放 chunk 序列等价

    func test_recordAndReplay_chunkSequenceEquivalent() async throws {
        let mockChunks: [ChatChunk] = [
            .text("你好"),
            .toolCall(id: "call_1", name: "patent_search", arguments: "{\"query\":\"CN123\"}"),
            .finish(reason: .toolCalls, usage: Usage(promptTokens: 100, completionTokens: 50, totalTokens: 150))
        ]
        let mock = MockModelBackend(provider: .deepseek, chunks: mockChunks)
        let recorder = HTTPFixtureRecorder(wrapping: mock)
        let req = ChatRequest(model: "deepseek-chat", messages: [Message(role: .user, content: "hi")])

        let recorded: [ChatChunk] = try await collectChunks(recorder.chat(req))
        XCTAssertEqual(recorded.count, 3)

        let doc: FixtureDocument = recorder.exportFixture()
        XCTAssertEqual(doc.provider, "deepseek")
        XCTAssertEqual(doc.records.count, 1)
        XCTAssertEqual(doc.records[0].requestModel, "deepseek-chat")
        XCTAssertEqual(doc.records[0].requestMessageCount, 1)
        XCTAssertEqual(doc.records[0].chunks.count, 3)

        let replay: ReplayModelBackend = ReplayModelBackend(provider: .deepseek, fixture: doc)
        let replayed: [ChatChunk] = try await collectChunks(replay.chat(req))

        XCTAssertEqual(recorded.count, replayed.count)
        if case .text(let text) = replayed[0] { XCTAssertEqual(text, "你好") } else { XCTFail("Expected .text at 0") }
        if case .toolCall(let id, let name, _) = replayed[1] {
            XCTAssertEqual(id, "call_1")
            XCTAssertEqual(name, "patent_search")
        } else {
            XCTFail("Expected .toolCall at 1")
        }
        if case .finish(let reason, let usage) = replayed[2] {
            XCTAssertEqual(reason, .toolCalls)
            XCTAssertEqual(usage?.promptTokens, 100)
            XCTAssertEqual(usage?.completionTokens, 50)
            XCTAssertEqual(usage?.totalTokens, 150)
        } else {
            XCTFail("Expected .finish at 2")
        }
    }

    // MARK: - usage 完整保留

    func test_usagePreserved_throughReplay() async throws {
        let usage = Usage(promptTokens: 200, completionTokens: 100, totalTokens: 300)
        let mock = MockModelBackend(provider: .openai, chunks: [.finish(reason: .stop, usage: usage)])
        let recorder: HTTPFixtureRecorder = HTTPFixtureRecorder(wrapping: mock)
        _ = try await collectChunks(recorder.chat(ChatRequest(model: "gpt-4o", messages: [])))

        let replay: ReplayModelBackend = ReplayModelBackend(provider: .openai, fixture: recorder.exportFixture())
        let chunks: [ChatChunk] = try await collectChunks(replay.chat(ChatRequest(model: "gpt-4o", messages: [])))
        guard case .finish(_, let usage) = chunks[0] else {
            XCTFail("Expected .finish")
            return
        }
        XCTAssertEqual(usage?.promptTokens, 200)
        XCTAssertEqual(usage?.completionTokens, 100)
        XCTAssertEqual(usage?.totalTokens, 300)
    }

    // MARK: - JSON 序列化往返

    func test_jsonSerialization_roundtrip() async throws {
        let doc = FixtureDocument(
            provider: "deepseek",
            records: [
                FixtureRecord(
                    requestModel: "test", requestMessageCount: 1,
                    chunks: [
                        .text("hello"),
                        .finish(reason: .stop, usage: Usage(promptTokens: 10, completionTokens: 5, totalTokens: 15))
                    ])
            ])
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(FixtureDocument.self, from: data)
        XCTAssertEqual(decoded.provider, "deepseek")
        XCTAssertEqual(decoded.records.count, 1)
        XCTAssertEqual(decoded.records[0].chunks.count, 2)
        XCTAssertEqual(decoded.records[0].chunks[0].kind, "text")
        XCTAssertEqual(decoded.records[0].chunks[0].text, "hello")
        XCTAssertEqual(decoded.records[0].chunks[1].usage?.totalTokens, 15)
    }

    func test_jsonString_init() async throws {
        let json: String = """
            {"version":1,"provider":"test",\
            "records":[{"requestModel":"m","requestMessageCount":0,"chunks":[{"kind":"text","text":"ok"}]}]}
            """
        let replay: ReplayModelBackend = try ReplayModelBackend(provider: .openai, jsonString: json)
        let chunks: [ChatChunk] = try await collectChunks(replay.chat(ChatRequest(model: "m", messages: [])))
        if case .text(let text) = chunks[0] { XCTAssertEqual(text, "ok") } else { XCTFail("Expected .text") }
    }

    // MARK: - 多次调用顺序回放

    func test_multipleCalls_sequentialReplay() async throws {
        let call1 = MockModelBackend(provider: .openai, chunks: [.text("first")])
        let recorder = HTTPFixtureRecorder(wrapping: call1)
        _ = try await collectChunks(recorder.chat(ChatRequest(model: "m", messages: [])))

        // 第二次用不同 mock（通过 responder 模式）
        let call2 = MockModelBackend(provider: .openai, chunks: [.text("second"), .finish(reason: .stop, usage: nil)])
        let recorder2 = HTTPFixtureRecorder(wrapping: call2)
        _ = try await collectChunks(recorder2.chat(ChatRequest(model: "m", messages: [])))

        // 合并两个 fixture
        var merged = recorder.exportFixture()
        merged.records.append(contentsOf: recorder2.exportFixture().records)
        XCTAssertEqual(merged.records.count, 2)

        let replay: ReplayModelBackend = ReplayModelBackend(provider: .openai, fixture: merged)
        let replay1: [ChatChunk] = try await collectChunks(replay.chat(ChatRequest(model: "m", messages: [])))
        let replay2: [ChatChunk] = try await collectChunks(replay.chat(ChatRequest(model: "m", messages: [])))
        if case .text(let text) = replay1[0] { XCTAssertEqual(text, "first") } else { XCTFail("Expected .text") }
        if case .text(let text) = replay2[0] { XCTAssertEqual(text, "second") } else { XCTFail("Expected .text") }
    }

    // MARK: - 耗尽错误

    func test_exhausted_throwsError() async throws {
        let doc = FixtureDocument(provider: "test", records: [])
        let replay = ReplayModelBackend(provider: .openai, fixture: doc)
        do {
            _ = try await collectChunks(replay.chat(ChatRequest(model: "", messages: [])))
            XCTFail("Should throw FixtureExhaustedError")
        } catch let err as FixtureExhaustedError {
            XCTAssertEqual(err.requestsMade, 0)
            XCTAssertEqual(err.requestsRecorded, 0)
        } catch {
            XCTFail("Expected FixtureExhaustedError, got \(type(of: error))")
        }
    }

    // MARK: - 错误流录制

    func test_errorStream_recorded() async throws {
        let mock = MockModelBackend(provider: .openai, shouldFail: true)
        let recorder = HTTPFixtureRecorder(wrapping: mock)
        _ = try? await collectChunks(recorder.chat(ChatRequest(model: "m", messages: [])))

        let doc = recorder.exportFixture()
        XCTAssertEqual(doc.records.count, 1, "错误流也应被录制为一条 record")
        XCTAssertEqual(doc.records[0].chunks.count, 1)
        XCTAssertEqual(doc.records[0].chunks[0].kind, "error")
    }

    // MARK: - reset 重置回放指针

    func test_reset_replayPointer() async throws {
        let doc = FixtureDocument(
            provider: "test",
            records: [
                FixtureRecord(requestModel: "m", requestMessageCount: 0, chunks: [.text("once")])
            ])
        let replay: ReplayModelBackend = ReplayModelBackend(provider: .openai, fixture: doc)
        let replay1: [ChatChunk] = try await collectChunks(replay.chat(ChatRequest(model: "m", messages: [])))
        XCTAssertEqual(replay1.count, 1)

        replay.reset()
        let replay2: [ChatChunk] = try await collectChunks(replay.chat(ChatRequest(model: "m", messages: [])))
        XCTAssertEqual(replay2.count, 1, "reset 后可重新回放")
    }

    // MARK: - saveFixture 文件写入

    func test_saveFixture_writesJSON() async throws {
        let mock = MockModelBackend(provider: .openai, chunks: [.text("saved"), .finish(reason: .stop, usage: nil)])
        let recorder = HTTPFixtureRecorder(wrapping: mock)
        _ = try await collectChunks(recorder.chat(ChatRequest(model: "m", messages: [])))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "test-fixture-\(UUID().uuidString).json")
        try recorder.saveFixture(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let replay: ReplayModelBackend = try ReplayModelBackend(provider: .openai, fixtureURL: url)
        let chunks: [ChatChunk] = try await collectChunks(replay.chat(ChatRequest(model: "m", messages: [])))
        if case .text(let text) = chunks[0] { XCTAssertEqual(text, "saved") } else { XCTFail("Expected .text") }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Helper

    private func collectChunks(_ stream: AsyncThrowingStream<ChatChunk, any Error>) async throws -> [ChatChunk] {
        var result: [ChatChunk] = []
        for try await chunk in stream { result.append(chunk) }
        return result
    }
}
