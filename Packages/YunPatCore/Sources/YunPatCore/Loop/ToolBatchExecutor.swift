import Foundation

// 并行工具批处理器 — 权限串行审批 + TaskGroup 并行执行，支持 intercept 和 dedup
//
// 两阶段设计：
// 1. 权限 gate 按模型顺序串行 resolve
// 2. 批准集 TaskGroup 并行执行，结果按模型顺序还原
//
// 规则：
// - intercept（complete/clarify）强制串行
// - intra-batch dedup：读类重复预先判定
// - state-before-cancel：结果先入 taskState 再处理 cancel

public struct ToolBatchExecutor: Sendable {

    public static let shared: ToolBatchExecutor = ToolBatchExecutor()

    /// intercept 工具名集合
    public static let interceptToolNames: Set<String> = [
        "complete", "task_complete", "clarify", "ask_user"
    ]

    private init() {}

    // 执行一批工具调用（非 inout 版本，返回结果和状态更新）
    // swiftlint:disable:next function_parameter_count function_body_length
    public func execute(
        calls: [ToolCall],
        ctx: ToolContext,
        stateSnapshot: PatentHarnessTaskState,
        executor: @escaping @Sendable (ToolCall) async -> ToolEnvelope,
        permissionGate: @escaping @Sendable (ToolCall) async -> Bool,
        preExecutionGate: @escaping @Sendable (ToolCall) async -> PreExecutionDecision,
        onIntercept: @escaping @Sendable (ToolCall, ToolEnvelope) async -> InterceptAction
    ) async -> (results: [ToolEnvelope], state: PatentHarnessTaskState) {
        var taskState: PatentHarnessTaskState = stateSnapshot

        let hasIntercept: Bool = calls.contains { Self.interceptToolNames.contains($0.name) }

        if hasIntercept {
            let results: [ToolEnvelope] = await executeSerial(
                calls: calls, taskState: &taskState,
                executor: executor, permissionGate: permissionGate,
                preExecutionGate: preExecutionGate, onIntercept: onIntercept
            )
            return (results, taskState)
        }

        // 两阶段审批
        var approved: [Int] = []
        // 预判 intra-batch dedup
        var deduped: [Int: String] = [:]
        var results: [(Int, ToolEnvelope)] = []

        // Phase 1: 权限串行 resolve + pre-execution gate + dedup 预判
        for (index, call) in calls.enumerated() {
            guard await permissionGate(call) else {
                results.append(
                    (
                        index,
                        ToolEnvelope(
                            toolName: call.name, content: "⚠️ 工具被拒绝: \(call.name)",
                            kind: .error, isError: true
                        )
                    ))
                continue
            }

            let preDecision: PreExecutionDecision = await preExecutionGate(call)
            if case .deny(let reason) = preDecision {
                results.append(
                    (
                        index,
                        ToolEnvelope(
                            toolName: call.name, content: "⚠️ 工具被拦截: \(reason)"
                        )
                    ))
                continue
            }

            approved.append(index)

            if taskState.deduplicate(call: call),
                let replay = taskState.replay(for: call) {
                deduped[index] = replay
            }
        }

        let toExecute: [Int] = approved.filter { !deduped.keys.contains($0) }
        var executedResults: [(Int, ToolEnvelope)] = []

        if !toExecute.isEmpty {
            await withTaskGroup(of: (Int, ToolEnvelope).self) { group in
                for index in toExecute {
                    let call: ToolCall = calls[index]
                    group.addTask {
                        let env: ToolEnvelope = await executor(call)
                        return (index, env)
                    }
                }
                for await result in group {
                    executedResults.append(result)
                }
            }
        }

        for index in approved {
            if let replayContent = deduped[index] {
                results.append((index, ToolEnvelope(toolName: calls[index].name, content: replayContent)))
            } else if let executed = executedResults.first(where: { $0.0 == index }) {
                taskState.record(call: calls[index], envelope: executed.1)
                results.append(executed)
            }
        }

        return (results.sorted { $0.0 < $1.0 }.map { $0.1 }, taskState)
    }

    // 串行执行（含 intercept 检测）
    // swiftlint:disable:next function_parameter_count
    private func executeSerial(
        calls: [ToolCall],
        taskState: inout PatentHarnessTaskState,
        executor: @escaping @Sendable (ToolCall) async -> ToolEnvelope,
        permissionGate: @escaping @Sendable (ToolCall) async -> Bool,
        preExecutionGate: @escaping @Sendable (ToolCall) async -> PreExecutionDecision,
        onIntercept: @escaping @Sendable (ToolCall, ToolEnvelope) async -> InterceptAction
    ) async -> [ToolEnvelope] {
        var results: [ToolEnvelope] = []

        for call in calls {
            guard await permissionGate(call) else {
                results.append(
                    ToolEnvelope(
                        toolName: call.name, content: "⚠️ 工具被拒绝: \(call.name)",
                        kind: .error, isError: true
                    ))
                continue
            }

            let preDecision: PreExecutionDecision = await preExecutionGate(call)
            if case .deny(let reason) = preDecision {
                results.append(
                    ToolEnvelope(
                        toolName: call.name, content: "⚠️ 工具被拦截: \(reason)"
                    ))
                continue
            }

            if !Self.interceptToolNames.contains(call.name),
                taskState.deduplicate(call: call),
                let replay = taskState.replay(for: call) {
                results.append(ToolEnvelope(toolName: call.name, content: replay))
                continue
            }

            let env: ToolEnvelope = await executor(call)
            taskState.record(call: call, envelope: env)

            let action: InterceptAction = await onIntercept(call, env)
            results.append(env)
            switch action {
            case .endRun:
                // skip remaining
                for skip in calls.dropFirst(results.count) {
                    results.append(ToolEnvelope(toolName: skip.name, content: "Skipped after endRun"))
                }
                return results
            case .skipSiblings:
                for skip in calls.dropFirst(results.count) {
                    results.append(ToolEnvelope(toolName: skip.name, content: "Skipped after intercept"))
                }
                return results
            case .continue:
                break
            }
        }

        return results
    }
}

// MARK: - InterceptAction

/// 拦截动作 — 工具执行后的流程控制决策（continue / endRun / skipSiblings）
public enum InterceptAction: Sendable {
    case `continue`
    case endRun
    case skipSiblings
}
