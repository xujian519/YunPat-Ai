import Foundation

// MARK: - Stuck File Guard

/// 编辑失败检测和恢复指引 — 防止 Agent 在同一文件上卡死
///
/// 设计参考 Agent-main (macOS26/Agent) 的 StuckGuard:
/// - 同一文件连续编辑失败 2 次 → 注入恢复提示 (重新读取、切换工具)
/// - 6 次失败 → 放弃该文件继续前进
/// - 成功后重置计数
public struct StuckGuard: Sendable {

    /// 编辑失败追踪: [filePath: failureCount]
    private var failures: [String: Int] = [:]

    /// 需要触发恢复提示的阈值
    public let nudgeThreshold: Int
    /// 需要放弃的阈值
    public let giveUpThreshold: Int

    /// 被视为编辑工具的工具名集合
    public let editTools: Set<String>

    public init(
        nudgeThreshold: Int = 2,
        giveUpThreshold: Int = 6,
        editTools: Set<String> = [
            "write_file",
            "edit_file",
            "diff_apply",
            "diff_and_apply",
            "apply_diff"
        ]
    ) {
        self.nudgeThreshold = nudgeThreshold
        self.giveUpThreshold = giveUpThreshold
        self.editTools = editTools
    }

    // MARK: - Detection

    /// 根据工具输出文本判断是否为失败
    public static func isFailure(output: String) -> Bool {
        let lower = output.lowercased()
        return lower.hasPrefix("error")
            || lower.contains("error:")
            || lower.contains("failed")
            || lower.contains("not found")
            || lower.contains("rejected")
    }

    /// 检测编辑失败，达到阈值时返回恢复指引或放弃通知
    public mutating func check(
        toolName: String,
        filePath: String?,
        result: String
    ) -> StuckNudge? {
        guard editTools.contains(toolName),
            let path = filePath
        else {
            return nil
        }

        if Self.isFailure(output: result) {
            failures[path, default: 0] += 1
            let count: Int = failures[path] ?? 0

            if count == nudgeThreshold {
                return StuckNudge(
                    level: .warn,
                    path: path,
                    message: recoveryNudge(path: path),
                    resetAfter: false
                )
            } else if count >= giveUpThreshold {
                // 重置计数，下次从零开始
                failures[path] = 0
                return StuckNudge(
                    level: .giveUp,
                    path: path,
                    message: giveUpNudge(path: path),
                    resetAfter: true
                )
            }
        } else {
            // 成功 → 重置计数
            failures[path] = 0
        }

        return nil
    }

    /// 重置指定文件的失败计数（成功后调用）
    public mutating func reset(filePath: String) {
        failures[filePath] = 0
    }

    /// 重置所有文件的失败计数
    public mutating func resetAll() {
        failures.removeAll()
    }

    // MARK: - Nudge Messages

    private func recoveryNudge(path: String) -> String {
        """
        ⚠️ \(nudgeThreshold) 次连续编辑失败: \(path)。停止重复相同方法。

        恢复检查清单 (按顺序):
        1. 重新 read_file(\(path))，获取最新完整内容 —— 不要信任之前的读取结果
        2. 精确找到要修改的行号
        3. 逐文件操作，确认当前文件正确后再处理下一个
        4. 若持续失败，换用不同工具 (如 write_file 覆写整个文件)
        """
    }

    private func giveUpNudge(path: String) -> String {
        """
        🛑 \(giveUpThreshold) 次失败: \(path)。
        停止编辑此文件。继续任务的其余部分或调用 task_complete 报告已完成内容。
        """
    }
}

// MARK: - Stuck Nudge Type

/// 陷入提示等级
public enum StuckNudgeLevel: Sendable {
    /// 警告 — 注入恢复指引后继续
    case warn
    /// 放弃 — 跳过此文件继续前进
    case giveUp
}

/// 检测到的陷入事件
public struct StuckNudge: Sendable {
    public let level: StuckNudgeLevel
    public let path: String
    public let message: String
    /// 注入消息后是否重置此文件的失败计数
    public let resetAfter: Bool
}

// MARK: - Loop Guard

/// 循环守卫 — 防止 Agent Loop 陷入死循环
///
/// 参考 Agent-main 的循环守卫:
/// - 迭代上限 nudging: 接近 maxIterations 时注入提示
/// - 连续读取警告: N 次连续 read 无 write 时提醒
public struct LoopGuard: Sendable {
    public let maxIterations: Int
    public let maxConsecutiveReads: Int

    public init(maxIterations: Int = 20, maxConsecutiveReads: Int = 10) {
        self.maxIterations = maxIterations
        self.maxConsecutiveReads = maxConsecutiveReads
    }

    /// 检查迭代次数并返回需要注入的消息
    public func checkIteration(_ iteration: Int) -> String? {
        if iteration == maxIterations {
            return "⏱ 迭代 \(iteration)/\(maxIterations) — 请在下一轮调用 task_complete 汇总已完成内容。这是最后机会——不再执行工具调用。"
        }
        if iteration > maxIterations {
            return "⏱ 强制终止 — 已达迭代上限 (\(maxIterations))。请汇总已完成内容作为 task_complete。"
        }
        return nil
    }

    /// 检查连续只读次数
    public func checkConsecutiveReads(_ count: Int) -> String? {
        if count == maxConsecutiveReads {
            return "🛑 连续 \(maxConsecutiveReads) 次读取无编辑。你只有两条路：缩小到一条具体发现去查证，或调用 task_complete 诚实报告未知项。禁止从部分读取中构造综合结论。"
        }
        return nil
    }
}
