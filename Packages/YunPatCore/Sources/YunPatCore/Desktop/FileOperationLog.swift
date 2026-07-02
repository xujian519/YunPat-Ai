import Foundation

/// 文件操作日志 — 会话内精确撤销（零依赖，GIS 回滚的前置过渡方案）
///
/// 每条操作包含 beforeContent（编辑前的原始内容），撤销时恢复原文。
/// write_file/edit_file 执行成功后自动 log（dry_run 不 log）。
/// shell 的 mv/cp/rm/mkdir 通过 ShellMutationLog 单独处理。
public actor FileOperationLog {
    public static let shared: FileOperationLog = FileOperationLog()

    private var operations: [FileOp] = []
    private var nextBatchId: UInt64 = 0

    private init() {}

    // MARK: - Log

    /// 记录一次文件写操作
    public func logWrite(path: String, content: String, beforeContent: String?) {
        let operation: FileOp = FileOp(
            id: UUID(),
            kind: .write,
            path: path,
            beforeContent: beforeContent,
            afterContent: content,
            timestamp: Date(),
            canUndo: beforeContent != nil,
            batchId: nil
        )
        operations.append(operation)
    }

    /// 记录一次文件编辑操作
    public func logEdit(path: String, afterContent: String, beforeContent: String?) {
        let operation: FileOp = FileOp(
            id: UUID(),
            kind: .edit,
            path: path,
            beforeContent: beforeContent,
            afterContent: afterContent,
            timestamp: Date(),
            canUndo: beforeContent != nil,
            batchId: nil
        )
        operations.append(operation)
    }

    /// 开始一个 batch（shell 多操作分批组）
    public func beginBatch() -> UInt64 {
        nextBatchId += 1
        return nextBatchId
    }

    /// 记录 shell 操作到指定 batch
    public func logShell(kind: FileOpKind, path: String, beforeContent: String?, canUndo: Bool) {
        let operation: FileOp = FileOp(
            id: UUID(),
            kind: kind,
            path: path,
            beforeContent: beforeContent,
            afterContent: nil,
            timestamp: Date(),
            canUndo: canUndo,
            batchId: nextBatchId
        )
        operations.append(operation)
    }

    // MARK: - Query

    /// 获取操作历史（可按 path 筛选）
    public func history(path: String? = nil) -> [FileOp] {
        if let path = path {
            return operations.filter { $0.path == path }.reversed()
        }
        return operations.reversed()
    }

    // MARK: - Undo

    /// 撤销最近 N 个可撤销的操作
    public func undoLast(count: Int = 1) async -> [String] {
        var results: [String] = []
        var undone: Int = 0
        for index in operations.indices.reversed() {
            guard undone < count else { break }
            let operation: FileOp = operations[index]
            guard operation.canUndo, let before: String = operation.beforeContent else { continue }
            do {
                try before.write(toFile: operation.path, atomically: true, encoding: .utf8)
                operations[index] = FileOp(
                    id: operation.id, kind: operation.kind, path: operation.path,
                    beforeContent: operation.beforeContent, afterContent: nil,
                    timestamp: operation.timestamp, canUndo: false, batchId: operation.batchId
                )
                results.append("✅ 已撤销: `\(operation.path)` (\(operation.kind))")
                undone += 1
            } catch {
                results.append("❌ 撤销失败: `\(operation.path)` - \(error.localizedDescription)")
            }
        }
        if results.isEmpty {
            results.append("没有可撤销的操作。")
        }
        return results
    }

    /// 撤销指定 opId
    public func undo(opId: UUID) async -> String {
        guard let idx = operations.firstIndex(where: { $0.id == opId }) else {
            return "Error: 未找到操作 \(opId)"
        }
        let operation: FileOp = operations[idx]
        guard operation.canUndo, let before: String = operation.beforeContent else {
            return "Error: 此操作不可撤销（无原始内容）"
        }
        do {
            try before.write(toFile: operation.path, atomically: true, encoding: .utf8)
            operations[idx] = FileOp(
                id: operation.id, kind: operation.kind, path: operation.path,
                beforeContent: operation.beforeContent, afterContent: nil,
                timestamp: operation.timestamp, canUndo: false, batchId: operation.batchId
            )
            return "✅ 已撤销: `\(operation.path)` (\(operation.kind))"
        } catch {
            return "❌ 撤销失败: `\(operation.path)` - \(error.localizedDescription)"
        }
    }

    /// 撤销某 path 所有可撤销操作
    public func undoAll(path: String) async -> [String] {
        var results: [String] = []
        for index in operations.indices.reversed() {
            let operation: FileOp = operations[index]
            guard operation.path == path, operation.canUndo, let before: String = operation.beforeContent else {
                continue
            }
            do {
                try before.write(toFile: operation.path, atomically: true, encoding: .utf8)
                operations[index] = FileOp(
                    id: operation.id, kind: operation.kind, path: operation.path,
                    beforeContent: operation.beforeContent, afterContent: nil,
                    timestamp: operation.timestamp, canUndo: false, batchId: operation.batchId
                )
                results.append("✅ 已撤销: `\(operation.path)` (\(operation.kind))")
            } catch {
                results.append("❌ 撤销失败: `\(operation.path)` - \(error.localizedDescription)")
            }
        }
        if results.isEmpty {
            results.append("`\(path)` 没有可撤销的操作。")
        }
        return results
    }

    /// 清空（session 结束）
    public func clear() {
        operations.removeAll()
    }
}

// MARK: - FileOp

public struct FileOp: Sendable {
    public let id: UUID
    public let kind: FileOpKind
    public let path: String
    public let beforeContent: String?
    public let afterContent: String?
    public let timestamp: Date
    public let canUndo: Bool
    public let batchId: UInt64?

    public init(
        id: UUID, kind: FileOpKind, path: String, beforeContent: String?, afterContent: String?, timestamp: Date,
        canUndo: Bool, batchId: UInt64?
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.beforeContent = beforeContent
        self.afterContent = afterContent
        self.timestamp = timestamp
        self.canUndo = canUndo
        self.batchId = batchId
    }
}

public enum FileOpKind: String, Sendable {
    case write
    case edit
    case move
    case copy
    case delete
    case mkdir
}

// MARK: - ShellMutationLog

/// Shell 操作规划与日志（mv/cp/rm/mkdir）
/// 执行前规划，将可解析的命令拆为多个 FileOp；退出码 0 后提交。
/// 无法忠实解析的（管道/glob/重定向）标记 unloggable。
public actor ShellMutationLog {
    public static let shared: ShellMutationLog = ShellMutationLog()

    private init() {}

    /// 解析命令，返回可撤销的操作规划
    /// - Returns: nil = 不可解析（unloggable）；空数组 = 无副作用
    public func plan(command: String, projectFolder: String) -> [PlannedMutation]? {
        let trimmed: String = command.trimmingCharacters(in: .whitespaces)
        let parts: [String] = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        guard !parts.isEmpty else { return [] }

        // 拒绝管道、重定向、glob
        let hasUnsafeTokens: Bool =
            trimmed.contains("|") || trimmed.contains(">")
            || trimmed.contains("*") || trimmed.contains("&&") || trimmed.contains("||")
        if hasUnsafeTokens { return nil }

        switch parts[0] {
        case "mv":
            guard parts.count >= 3 else { return [] }
            let src: String = resolve(parts[1], base: projectFolder)
            let dst: String = resolve(parts[parts.count - 1], base: projectFolder)
            return [PlannedMutation(kind: .move, sourcePath: src, destPath: dst, preserveContent: src)]

        case "cp":
            guard parts.count >= 3 else { return [] }
            let src: String = resolve(parts[1], base: projectFolder)
            let dst: String = resolve(parts[parts.count - 1], base: projectFolder)
            return [PlannedMutation(kind: .copy, sourcePath: src, destPath: dst, preserveContent: nil)]

        case "rm":
            guard parts.count >= 2 else { return [] }
            let path: String = resolve(parts[1], base: projectFolder)
            let beforeContent: String? = try? String(contentsOfFile: path, encoding: .utf8)
            return [PlannedMutation(kind: .delete, sourcePath: path, destPath: nil, preserveContent: beforeContent)]

        case "mkdir":
            guard parts.count >= 2 else { return [] }
            let path: String = resolve(parts[1], base: projectFolder)
            return [PlannedMutation(kind: .mkdir, sourcePath: path, destPath: nil, preserveContent: nil)]

        default:
            return []  // 其他命令无副作用或不可解析
        }
    }

    /// 提交规划（退出码 0 时调用）
    public func commit(_ mutations: [PlannedMutation]) async {
        for mutation in mutations {
            switch mutation.kind {
            case .move:
                await FileOperationLog.shared.logShell(
                    kind: .move, path: mutation.sourcePath, beforeContent: mutation.preserveContent, canUndo: true)
            case .copy:
                await FileOperationLog.shared.logShell(
                    kind: .copy, path: mutation.destPath ?? mutation.sourcePath, beforeContent: nil, canUndo: false)
            case .delete:
                await FileOperationLog.shared.logShell(
                    kind: .delete, path: mutation.sourcePath, beforeContent: mutation.preserveContent,
                    canUndo: mutation.preserveContent != nil)
            case .mkdir:
                await FileOperationLog.shared.logShell(
                    kind: .mkdir, path: mutation.sourcePath, beforeContent: nil, canUndo: false)
            default:
                break
            }
        }
    }

    private func resolve(_ path: String, base: String) -> String {
        if path.hasPrefix("/") { return path }
        return (base as NSString).appendingPathComponent(path)
    }
}

// MARK: - PlannedMutation

public struct PlannedMutation: @unchecked Sendable {
    public let kind: FileOpKind
    public let sourcePath: String
    public let destPath: String?
    /// 对 mv 是原始路径；对 rm 是文件内容（string）；对 cp/mkdir 是 nil
    public let preserveContent: String?

    public init(kind: FileOpKind, sourcePath: String, destPath: String?, preserveContent: String?) {
        self.kind = kind
        self.sourcePath = sourcePath
        self.destPath = destPath
        self.preserveContent = preserveContent
    }
}
