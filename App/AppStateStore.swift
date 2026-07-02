import Combine
import SwiftUI

/// Combine 响应式状态管理中心
@MainActor
public final class AppStateStore: ObservableObject, @unchecked Sendable {
    public static let shared = AppStateStore()

    @Published public var sidebarCollapsed: Bool = false
    @Published public var collaborationVisible: Bool = false
    @Published public var browserVisible: Bool = false
    @Published public var documentSplitVisible: Bool = false
    @Published public var caseGraphMode: Bool = false
    @Published public var isStreaming: Bool = false
    @Published public var connectionStatus: String = "已连接"

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
