import Combine
import SwiftUI

// MARK: - Dock Panel Enums

public enum LeftDockPanel: String, CaseIterable, Codable {
    case projectList
}

public enum RightDockPanel: String, CaseIterable, Codable, Identifiable {
    case collaboration
    case caseGraph
    case costDashboard
    case memoryAudit
    case toolAudit
    case fileExplorer
    case document
    case skills
    case routing
    case memory
    case alwaysOn
    case browser

    public var id: String { rawValue }

    public var isPersistentModule: Bool {
        switch self {
        case .fileExplorer, .document, .skills, .routing, .memory, .alwaysOn, .browser:
            return true
        case .collaboration, .caseGraph, .costDashboard, .memoryAudit, .toolAudit:
            return false
        }
    }
}

/// 顶部主导航模块，与 PilotDeck 对齐
public enum TopModule: String, CaseIterable, Codable, Identifiable {
    case agent = "智能体"
    case files = "文件"
    case skills = "技能"
    case routing = "路由"
    case memory = "记忆"
    case alwaysOn = "常驻"

    public var id: String { rawValue }

    var icon: String {
        switch self {
        case .agent: return "sparkles"
        case .files: return "folder"
        case .skills: return "wand.and.stars"
        case .routing: return "chart.pie"
        case .memory: return "brain.head.profile"
        case .alwaysOn: return "waveform"
        }
    }

    /// 用于 ⌘1~6 快捷键的数字字符
    var shortcutDigit: String {
        switch self {
        case .agent: return "1"
        case .files: return "2"
        case .skills: return "3"
        case .routing: return "4"
        case .memory: return "5"
        case .alwaysOn: return "6"
        }
    }

    /// 用于键盘快捷键的 KeyEquivalent
    var shortcutKey: KeyEquivalent {
        KeyEquivalent(Character(shortcutDigit))
    }
}

/// 中心区域内容模式。
public enum CenterMode: String, CaseIterable, Codable {
    case chat
    case browser
    case focusWriting
    case files
    case skills
    case routing
    case memory
    case alwaysOn
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
    @Published public var topModule: TopModule = .agent
    @Published public var leftDockActivePanel: LeftDockPanel = .projectList
    @Published public var rightDockActivePanel: RightDockPanel = .collaboration
    @Published public var selectedDocumentURL: URL?

    /// 专注写作退出时恢复的状态快照
    struct FocusWritingSnapshot {
        var leftVisible: Bool
        var rightVisible: Bool
        var bottomVisible: Bool
        var mode: CenterMode
        var module: TopModule
        var rightPanel: RightDockPanel
    }
    var focusWritingRestoreState: FocusWritingSnapshot?

    // MARK: - Module / Dock 切换

    /// 根据顶部模块切换中心内容区和右栏面板。
    /// 文件/技能/路由/记忆/常驻作为主工作区展示；右栏留给协作面板、审计、图表等辅助视图。
    public func switchToModule(_ module: TopModule) {
        topModule = module
        rightDockVisible = false
        switch module {
        case .agent:
            centerMode = .chat
        case .files:
            centerMode = .files
        case .skills:
            centerMode = .skills
        case .routing:
            centerMode = .routing
        case .memory:
            centerMode = .memory
        case .alwaysOn:
            centerMode = .alwaysOn
        }
    }

    public func openRightPanel(_ panel: RightDockPanel) {
        rightDockActivePanel = panel
        rightDockVisible = true
    }

    public func showDocument(url: URL) {
        selectedDocumentURL = url
        openRightPanel(.document)
    }

    public func showFileExplorer() {
        openRightPanel(.fileExplorer)
    }

    public func toggleRightPanel(_ panel: RightDockPanel) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if rightDockVisible && rightDockActivePanel == panel {
                rightDockVisible = false
            } else {
                openRightPanel(panel)
            }
        }
    }

    /// 进入专注写作：快照当前状态并隐藏所有 Dock
    func enterFocusWriting() {
        focusWritingRestoreState = FocusWritingSnapshot(
            leftVisible: leftDockVisible,
            rightVisible: rightDockVisible,
            bottomVisible: bottomDockVisible,
            mode: centerMode,
            module: topModule,
            rightPanel: rightDockActivePanel
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
            topModule = restore.module
            rightDockActivePanel = restore.rightPanel
            focusWritingRestoreState = nil
        } else {
            centerMode = .chat
            topModule = .agent
            rightDockActivePanel = .collaboration
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
