import SwiftUI
import Combine

/// Combine 响应式状态管理中心
@MainActor
public final class AppStateStore: ObservableObject, @unchecked Sendable {
    public static let shared = AppStateStore()

    @Published public var sidebarCollapsed = false
    @Published public var collaborationVisible = false
    @Published public var browserVisible = false
    @Published public var documentSplitVisible = false
    @Published public var caseGraphMode = false
    @Published public var isStreaming = false
    @Published public var connectionStatus = "已连接"

    // 撤销/重做
    public let undoManager = UndoManager()
    @Published public var canUndo = false
    @Published public var canRedo = false

    public func registerUndo(_ label: String, action: @escaping () -> Void) {
        undoManager.registerUndo(withTarget: self) { _ in
            action()
            self.updateUndoState()
        }
        undoManager.setActionName(label)
        updateUndoState()
    }

    public func undo() { undoManager.undo(); updateUndoState() }
    public func redo() { undoManager.redo(); updateUndoState() }

    private func updateUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }

    @Published public var documentChangeCount = 0
    public func notifyDocumentChange() { documentChangeCount += 1 }
}

