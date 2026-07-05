import Combine
import SwiftUI

// MARK: - Dock Panel Enums

public enum LeftDockPanel: String, CaseIterable, Codable {
    case caseList
    case caseWorkspace
    case knowledge  // 预留
}

public enum RightDockPanel: String, CaseIterable, Codable {
    case collaboration
    case caseGraph
    case costDashboard
    case memoryAudit
}

/// Combine 响应式状态管理中心
@MainActor
public final class AppStateStore: ObservableObject, @unchecked Sendable {
    public static let shared = AppStateStore()

    // ── Dock 系统（新统一状态，逐步替代旧变量）──

    @Published public var leftDockVisible: Bool = true
    @Published public var rightDockVisible: Bool = false
    @Published public var bottomDockVisible: Bool = false
    @Published public var centerMode: CenterMode = .chat
    @Published public var leftDockActivePanel: LeftDockPanel = .caseList
    @Published public var rightDockActivePanel: RightDockPanel = .collaboration

    /// 专注写作退出时恢复的状态快照
    struct FocusWritingSnapshot {
        var leftVisible: Bool
        var rightVisible: Bool
        var bottomVisible: Bool
        var mode: CenterMode
    }
    var focusWritingRestoreState: FocusWritingSnapshot?

    // MARK: - Focus Writing

    /// 进入专注写作：快照当前状态并隐藏所有 Dock
    func enterFocusWriting() {
        focusWritingRestoreState = FocusWritingSnapshot(
            leftVisible: leftDockVisible,
            rightVisible: rightDockVisible,
            bottomVisible: bottomDockVisible,
            mode: centerMode
        )
        leftDockVisible = false
        rightDockVisible = false
        bottomDockVisible = false
        centerMode = .focusWriting
    }

    func exitFocusWriting() {
        if let restore = focusWritingRestoreState {
            leftDockVisible = restore.leftVisible
            rightDockVisible = restore.rightVisible
            bottomDockVisible = restore.bottomVisible
            centerMode = restore.mode
            focusWritingRestoreState = nil
        } else {
            centerMode = .chat
        }
    }

    // ── 运行状态 ──

    @Published public var isStreaming: Bool = false

    // 撤销/重做
    public let undoManager = UndoManager()
    @Published public var canUndo: Bool = false
    @Published public var canRedo: Bool = false

    public func registerUndo(_ label: String, action: @escaping () -> Void) {
        undoManager.registerUndo(withTarget: self) { _ in
            action()
            self.updateUndoState()
        }
        undoManager.setActionName(label)
        updateUndoState()
    }

    public func undo() {
        undoManager.undo()
        updateUndoState()
    }
    public func redo() {
        undoManager.redo()
        updateUndoState()
    }

    private func updateUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }

    @Published public var documentChangeCount: Int = 0
    public func notifyDocumentChange() { documentChangeCount += 1 }
}
