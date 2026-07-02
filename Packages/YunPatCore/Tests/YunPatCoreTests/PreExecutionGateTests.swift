import XCTest
import YunPatNetworking

@testable import YunPatCore

final class PreExecutionGateTests: XCTestCase {

    // MARK: - deny 阻止工具执行，reason 喂回结果

    func test_deny_preventsExecution() async {
        let tracker = ExecutionTracker()

        let (results, _): (results: [ToolEnvelope], state: PatentHarnessTaskState) = await ToolBatchExecutor.shared.execute(
            calls: [ToolCall(id: "1", name: "read_file")],
            ctx: ToolContext(toolId: "1", projectFolder: "", selectedProvider: .openai),
            stateSnapshot: PatentHarnessTaskState(),
            executor: { _ in
                await tracker.track()
                return ToolEnvelope(toolName: "read_file", content: "executed")
            },
            permissionGate: { _ in true },
            preExecutionGate: { _ in .deny("预算已用完") },
            onIntercept: { _, _ in .continue }
        )

        let executed: Int = await tracker.count
        XCTAssertEqual(executed, 0, "工具不应执行")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].content.contains("预算已用完"))
        XCTAssertFalse(results[0].isError)
    }

    // MARK: - allow 正常执行

    func test_allow_executesNormally() async {
        let tracker = ExecutionTracker()

        let (results, _): (results: [ToolEnvelope], state: PatentHarnessTaskState) = await ToolBatchExecutor.shared.execute(
            calls: [ToolCall(id: "1", name: "read_file")],
            ctx: ToolContext(toolId: "1", projectFolder: "", selectedProvider: .openai),
            stateSnapshot: PatentHarnessTaskState(),
            executor: { _ in
                await tracker.track()
                return ToolEnvelope(toolName: "read_file", content: "data")
            },
            permissionGate: { _ in true },
            preExecutionGate: { _ in .allow },
            onIntercept: { _, _ in .continue }
        )

        let count: Int = await tracker.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(results[0].content, "data")
    }

    // MARK: - 多工具中部分 deny

    func test_partialDeny() async {
        let tracker = ExecutionTracker()

        let calls: [ToolCall] = [
            ToolCall(id: "1", name: "read_file"),
            ToolCall(id: "2", name: "write_file"),
            ToolCall(id: "3", name: "list_files")
        ]

        let (results, _): (results: [ToolEnvelope], state: PatentHarnessTaskState) = await ToolBatchExecutor.shared.execute(
            calls: calls,
            ctx: ToolContext(toolId: "", projectFolder: "", selectedProvider: .openai),
            stateSnapshot: PatentHarnessTaskState(),
            executor: { call in
                await tracker.track()
                return ToolEnvelope(toolName: call.name, content: "ok")
            },
            permissionGate: { _ in true },
            preExecutionGate: { call in
                call.name == "write_file" ? .deny("只读模式") : .allow
            },
            onIntercept: { _, _ in .continue }
        )

        let count: Int = await tracker.count
        XCTAssertEqual(count, 2, "只有 2 个工具被执行")
        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results[1].content.contains("只读模式"), "Got: \(results[1].content)")
    }

    // MARK: - 全部 deny

    func test_allDenied() async {
        let tracker = ExecutionTracker()

        let calls: [ToolCall] = [
            ToolCall(id: "1", name: "read_file"),
            ToolCall(id: "2", name: "write_file")
        ]

        let (results, _): (results: [ToolEnvelope], state: PatentHarnessTaskState) = await ToolBatchExecutor.shared.execute(
            calls: calls,
            ctx: ToolContext(toolId: "", projectFolder: "", selectedProvider: .openai),
            stateSnapshot: PatentHarnessTaskState(),
            executor: { _ in
                await tracker.track()
                return ToolEnvelope(toolName: "x", content: "should not run")
            },
            permissionGate: { _ in true },
            preExecutionGate: { _ in .deny("全部暂停") },
            onIntercept: { _, _ in .continue }
        )

        let count: Int = await tracker.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.content.contains("全部暂停") })
    }

    // MARK: - intercept 工具 + preExecutionGate 串行交互

    func test_interceptTool_withPreExecutionGate() async {
        let tracker = ExecutionTracker()

        let (results, _): (results: [ToolEnvelope], state: PatentHarnessTaskState) = await ToolBatchExecutor.shared.execute(
            calls: [
                ToolCall(id: "1", name: "read_file"),
                ToolCall(id: "2", name: "complete")
            ],
            ctx: ToolContext(toolId: "", projectFolder: "", selectedProvider: .openai),
            stateSnapshot: PatentHarnessTaskState(),
            executor: { call in
                await tracker.track()
                return ToolEnvelope(toolName: call.name, content: "ok")
            },
            permissionGate: { _ in true },
            preExecutionGate: { _ in .allow },
            onIntercept: { call, _ in
                call.name == "complete" ? .endRun : .continue
            }
        )

        let count: Int = await tracker.count
        XCTAssertGreaterThanOrEqual(count, 1, "至少 read_file 应执行")
        XCTAssertGreaterThanOrEqual(results.count, 2)
    }

    // MARK: - EventBus 集成：publish toolPreExecute

    func test_eventBus_publishesPreExecute() async {
        let bus = EventBus()
        let collector = EventCollector()

        _ = await bus.subscribe { event in await collector.append(event) }

        let preGate: @Sendable (ToolCall) async -> PreExecutionDecision = { call in
            await bus.publish(.toolPreExecute(toolName: call.name, callId: call.id))
            return .allow
        }

        _ = await ToolBatchExecutor.shared.execute(
            calls: [ToolCall(id: "x1", name: "read_file")],
            ctx: ToolContext(toolId: "x1", projectFolder: "", selectedProvider: .openai),
            stateSnapshot: PatentHarnessTaskState(),
            executor: { _ in ToolEnvelope(toolName: "read_file", content: "ok") },
            permissionGate: { _ in true },
            preExecutionGate: preGate,
            onIntercept: { _, _ in .continue }
        )

        let found: Bool = await collector.contains { event in
            if case .toolPreExecute(let name, let id) = event {
                return name == "read_file" && id == "x1"
            }
            return false
        }
        XCTAssertTrue(found)
    }

    // MARK: - EventBus 集成：publish toolDenied

    func test_eventBus_publishesDenied() async {
        let bus = EventBus()
        let collector = EventCollector()

        _ = await bus.subscribe { event in await collector.append(event) }

        let preGate: @Sendable (ToolCall) async -> PreExecutionDecision = { call in
            await bus.publish(.toolPreExecute(toolName: call.name, callId: call.id))
            let decision: PreExecutionDecision = call.name == "write_file" ? .deny("禁止") : .allow
            if case .deny(let reason) = decision {
                await bus.publish(.toolDenied(toolName: call.name, reason: reason))
            }
            return decision
        }

        _ = await ToolBatchExecutor.shared.execute(
            calls: [ToolCall(id: "1", name: "write_file")],
            ctx: ToolContext(toolId: "", projectFolder: "", selectedProvider: .openai),
            stateSnapshot: PatentHarnessTaskState(),
            executor: { _ in ToolEnvelope(toolName: "x", content: "no") },
            permissionGate: { _ in true },
            preExecutionGate: preGate,
            onIntercept: { _, _ in .continue }
        )

        let found: Bool = await collector.contains { event in
            if case .toolDenied(let name, let reason) = event {
                return name == "write_file" && reason == "禁止"
            }
            return false
        }
        XCTAssertTrue(found)
    }
}

// MARK: - Test Helpers

private actor ExecutionTracker {
    private(set) var count: Int = 0
    func track() { count += 1 }
}

private actor EventCollector {
    private(set) var events: [AgentEvent] = []
    func append(_ event: AgentEvent) { events.append(event) }
    func contains(predicate: @Sendable (AgentEvent) -> Bool) -> Bool {
        events.contains(where: predicate)
    }
}
