import SwiftUI
import YunPatCore
import YunPatNetworking

struct ContentView: View {
    @StateObject private var tabManager: TabManager = TabManager()
    @StateObject private var chatManager: ChatManager
    @StateObject private var workspaceManager: CaseWorkspaceManager = CaseWorkspaceManager()
    @State private var filePickerOpen: Bool = false
    @State private var showWizard: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Binding var windowTitle: String

    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    @AppStorage("yunpat.rightPanelWidth") private var rightPanelWidth: Double = Double(PanelWidth.rightPanelIdeal)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    init(router: ModelRouter, windowTitle: Binding<String>) {
        _chatManager = StateObject(wrappedValue: ChatManager(modelRouter: router))
        _windowTitle = windowTitle
    }

    var body: some View {
        Group {
            if appState.centerMode == .focusWriting {
                FocusWritingContent { appState.exitFocusWriting() }
            } else {
                navigationSplitView
            }
        }
        .accessibleAnimation(
            .easeInOut(duration: AnimationDuration.slow),
            value: appState.bottomDockVisible
        )
        .accessibleAnimation(
            .easeInOut(duration: AnimationDuration.slow),
            value: appState.centerMode
        )
        .modifier(
            ContentViewModifiers(
                windowTitle: $windowTitle,
                tabManager: tabManager,
                chatManager: chatManager,
                showWizard: $showWizard,
                filePickerOpen: $filePickerOpen
            )
        )
        .fileImporter(
            isPresented: $filePickerOpen,
            allowedContentTypes: [.plainText, .pdf, .data],
            allowsMultipleSelection: true,
            onCompletion: { result in
                chatManager.handleFileImport(result, in: tabManager)
            }
        )
        .onChange(of: activeTab?.caseId) { _, newCaseId in
            workspaceManager.selectedCaseId = newCaseId
        }
        .onChange(of: activeTab?.title) { _, newTitle in
            windowTitle = newTitle ?? "YunPat-Ai"
        }
        .onChange(of: appState.leftDockVisible) { _, visible in
            withAccessibleAnimation(reduceMotion: reduceMotion) {
                columnVisibility = visible ? .all : .detailOnly
            }
        }
        .task {
            workspaceManager.selectedCaseId = activeTab?.caseId
            windowTitle = activeTab?.title ?? "YunPat-Ai"
            columnVisibility = appState.leftDockVisible ? .all : .detailOnly
        }
        .withWindowRestoration()
    }

    // MARK: - NavigationSplitView

    private var navigationSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ProjectListSidebar(tabManager: tabManager)
                .navigationSplitViewColumnWidth(
                    min: PanelWidth.sidebarMin,
                    ideal: PanelWidth.sidebarIdeal,
                    max: PanelWidth.sidebarMax
                )
        } detail: {
            mainContentArea
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Main Content Area (center + right panel)

    private var mainContentArea: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if appState.centerMode == .chat {
                    TabStripContent(
                        tabManager: tabManager,
                        chatManager: chatManager
                    )
                    Divider()
                }

                centerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.appBackground)

            if appState.rightDockVisible {
                ResizableDivider(
                    minWidth: PanelWidth.rightPanelMin,
                    maxWidth: PanelWidth.rightPanelMax,
                    currentWidth: Binding<CGFloat>(
                        get: { CGFloat(rightPanelWidth) },
                        set: { rightPanelWidth = Double($0) }
                    ),
                    onWidthChange: { rightPanelWidth += Double($0) }
                )

                detailContent
                    .frame(width: CGFloat(rightPanelWidth))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                breadcrumb
            }
            ToolbarItemGroup(placement: .primaryAction) {
                moduleNavigation
            }
        }
    }

    // MARK: - Toolbar: Breadcrumb

    private var breadcrumb: some View {
        HStack(spacing: Spacing.xxs) {
            Text(currentProjectName)
                .foregroundStyle(Color.appTextSecondary)
            Text("/")
                .foregroundStyle(Color.appTextTertiary)
            Text(currentModuleName)
                .foregroundStyle(Color.appTextPrimary)
                .fontWeight(.medium)
            if let subtitle = currentSubtitle {
                Text(subtitle)
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(1)
            }
        }
        .font(FontStyle.callout)
    }

    // MARK: - Toolbar: Module Navigation

    private var moduleNavigation: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(TopModule.allCases) { module in
                Button {
                    switchToModule(module)
                } label: {
                    Label(module.rawValue, systemImage: module.icon)
                        .labelStyle(.titleAndIcon)
                        .font(FontStyle.callout)
                        .foregroundStyle(
                            appState.topModule == module
                                ? Color.accentColor
                                : Color.appTextSecondary
                        )
                }
                .help("\(module.rawValue) (⌘\(module.shortcutDigit))")
            }
        }
    }

    private var currentProjectName: String {
        activeTab?.title ?? "YunPat-Ai"
    }

    private var currentModuleName: String {
        appState.topModule.rawValue
    }

    private var currentSubtitle: String? {
        guard appState.centerMode == .chat || appState.centerMode == .browser,
            let tab = activeTab
        else { return nil }
        return tab.title
    }

    // MARK: - Main Section

    @ViewBuilder
    private var centerContent: some View {
        switch appState.centerMode {
        case .chat:
            ChatArea(
                tabManager: tabManager,
                chatManager: chatManager,
                onAttachFiles: { filePickerOpen = true }
            )
        case .files:
            FileBrowserView(workspaceManager: workspaceManager, tabManager: tabManager)
        case .skills:
            SkillGalleryView()
        case .routing:
            RoutingDashboardView()
        case .memory:
            MemoryDashboardView()
        case .alwaysOn:
            AlwaysOnDashboardView(tabManager: tabManager, chatManager: chatManager)
        case .browser:
            PatentBrowser()
        case .focusWriting:
            FocusWritingContent { appState.exitFocusWriting() }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        switch appState.rightDockActivePanel {
        case .collaboration:
            CollaborationPanel(tabManager: tabManager, chatManager: chatManager)
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
        case .caseGraph:
            CaseGraphView(caseId: activeTab?.caseId)
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
        case .costDashboard:
            CostDashboardView(caseId: activeTab?.caseId)
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
        case .memoryAudit:
            MemoryAuditView()
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
        case .toolAudit:
            ToolAuditView()
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
        case .fileExplorer:
            RightFileExplorerView(workspaceManager: workspaceManager, tabManager: tabManager)
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
        case .document:
            RightDocumentView()
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
        case .skills:
            RightSkillGalleryView()
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
        case .routing:
            RightRoutingDashboardView(caseId: activeTab?.caseId)
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
        case .memory:
            RightMemoryDashboardView(caseId: activeTab?.caseId)
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
        case .alwaysOn:
            RightAlwaysOnDashboardView()
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
        case .browser:
            PatentBrowser()
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
        }
    }

    // MARK: - Helpers

    private var activeTab: ChatTab? {
        guard let id = tabManager.activeTabID else { return nil }
        return tabManager.tabs.first(where: { $0.id == id })
    }

    private func switchToModule(_ module: TopModule) {
        withAccessibleAnimation(reduceMotion: reduceMotion, duration: AnimationDuration.fast) {
            appState.switchToModule(module)
        }
    }

    private func syncToAgent() {
        Task { await chatManager.sendDocumentAnnotations(in: tabManager) }
    }
}
