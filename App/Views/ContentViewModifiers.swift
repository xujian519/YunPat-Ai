import SwiftUI
import YunPatCore

struct ContentViewModifiers: ViewModifier {
    @Binding var windowTitle: String
    @ObservedObject var tabManager: TabManager
    @ObservedObject var chatManager: ChatManager
    @Binding var sidebarCollapsed: Bool
    @Binding var collaborationVisible: Bool
    @Binding var documentSplitVisible: Bool
    @Binding var browserVisible: Bool
    @Binding var focusWritingMode: Bool
    @Binding var showWizard: Bool
    @Binding var filePickerOpen: Bool

    func body(content: Content) -> some View {
        content
            .navigationTitle(windowTitle)
            .toolbar { toolbarGroup }
            .sheet(isPresented: $showWizard) {
                KnowledgeSetupWizard(isPresented: $showWizard)
            }
            .onAppear(perform: checkWizardNeeded)
            .onReceive(publisher(for: .menuNewTab)) { _ in
                tabManager.addTab()
            }
            .onReceive(publisher(for: .menuNewCase)) { _ in
                tabManager.addTab(type: .patent)
            }
            .onReceive(publisher(for: .menuOpenFile)) { _ in
                filePickerOpen = true
            }
            .onReceive(publisher(for: .menuToggleSidebar)) { _ in
                withAnimation { sidebarCollapsed.toggle() }
            }
            .onReceive(publisher(for: .menuToggleCollaboration)) { _ in
                withAnimation { collaborationVisible.toggle() }
            }
            .onReceive(publisher(for: .menuToggleBrowser)) { _ in
                withAnimation { browserVisible.toggle() }
            }
            .onReceive(publisher(for: .menuToggleSplitScreen)) { _ in
                withAnimation { documentSplitVisible.toggle() }
            }
            .onReceive(publisher(for: .menuFocusWriting)) { _ in
                withAnimation(.spring(duration: AnimationDuration.spring)) {
                    focusWritingMode.toggle()
                }
            }
            .onReceive(publisher(for: .menuUndo)) { _ in
                AppStateStore.shared.undo()
            }
            .onReceive(publisher(for: .menuRedo)) { _ in
                AppStateStore.shared.redo()
            }
    }

    private func publisher(for name: Notification.Name) -> NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: name)
    }

    private func checkWizardNeeded() {
        if UserDefaults.standard.string(forKey: "yunpat.vaultPath") == nil {
            showWizard = true
        }
    }

    @ToolbarContentBuilder
    private var toolbarGroup: some ToolbarContent {
        ToolbarItemGroup {
            Button(
                action: { withAnimation { sidebarCollapsed.toggle() } },
                label: { Label("侧栏", systemImage: "sidebar.left") }
            ).help("显示/隐藏侧栏")

            Button(
                action: openSettings,
                label: { Label("设置", systemImage: "gearshape") }
            ).help("打开设置")

            Spacer()
        }
    }

    private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
