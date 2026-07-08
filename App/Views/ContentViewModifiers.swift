import SwiftUI
import YunPatCore

struct ContentViewModifiers: ViewModifier {
    @Binding var windowTitle: String
    @ObservedObject var tabManager: TabManager
    @ObservedObject var chatManager: ChatManager
    @Binding var showWizard: Bool
    @Binding var filePickerOpen: Bool

    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    func body(content: Content) -> some View {
        content
            .navigationTitle(windowTitle)
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
            .onReceive(publisher(for: .menuOpenFolder)) { _ in
                openFolderAsProject()
            }
            .onReceive(publisher(for: .menuToggleSidebar)) { _ in
                withAnimation { appState.leftDockVisible.toggle() }
            }
            .onReceive(publisher(for: .menuToggleCollaboration)) { _ in
                withAnimation { appState.rightDockVisible.toggle() }
            }
            .onReceive(publisher(for: .menuToggleBrowser)) { _ in
                withAnimation {
                    appState.centerMode = appState.centerMode == .browser ? .chat : .browser
                }
            }
            .onReceive(publisher(for: .menuToggleSplitScreen)) { _ in
                withAnimation {
                    appState.leftDockVisible.toggle()
                }
            }
            .onReceive(publisher(for: .menuFocusWriting)) { _ in
                withAnimation(.spring(duration: AnimationDuration.spring)) {
                    if appState.centerMode == .focusWriting {
                        appState.exitFocusWriting()
                    } else {
                        appState.enterFocusWriting()
                    }
                }
            }
            .onReceive(publisher(for: .menuUndo)) { _ in
                appState.undo()
            }
            .onReceive(publisher(for: .menuRedo)) { _ in
                appState.redo()
            }
    }

    private func publisher(for name: Notification.Name) -> NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: name)
    }

    private func openFolderAsProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择项目文件夹"
        panel.message = "选择一个文件夹作为新项目的工作目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        tabManager.openFolderAsProject(url: url)
    }

    private func checkWizardNeeded() {
        if UserDefaults.standard.string(forKey: "yunpat.vaultPath") == nil {
            showWizard = true
        }
    }
}
