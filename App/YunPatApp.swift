import AppKit
import SwiftUI
import YunPatCore
import YunPatNetworking

@main
struct YunPatApp: App {
    @StateObject private var appState: AppState = AppState()
    @State private var activeTabTitle: String = "YunPat-Ai"

    var body: some Scene {
        WindowGroup {
            ContentView(router: appState.modelRouter, windowTitle: $activeTabTitle)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    for provider in providers {
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            guard let url = url else { return }
                            NotificationCenter.default.post(name: .dropFile, object: url)
                        }
                    }
                    return true
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // ── App Info ──
            CommandGroup(replacing: .appInfo) {
                Button("关于 YunPat-Ai") {
                    NSApp.orderFrontStandardAboutPanel(options: [:])
                }
            }

            // ── File Menu ──
            CommandGroup(replacing: .newItem) {
                Button("新建标签") {
                    NotificationCenter.default.post(name: .menuNewTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
                Button("新建案件") {
                    NotificationCenter.default.post(name: .menuNewCase, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("打开文件…") {
                    NotificationCenter.default.post(name: .menuOpenFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("保存当前文档") {
                    NotificationCenter.default.post(name: .menuSave, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            // ── Edit Menu (保留系统默认 undo/redo，仅添加自定义项) ──
            CommandGroup(after: .undoRedo) {
                Divider()
            }

            // ── View Menu ──
            CommandMenu("显示") {
                Button("切换侧栏") {
                    NotificationCenter.default.post(name: .menuToggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                Button("切换协作面板") {
                    NotificationCenter.default.post(name: .menuToggleCollaboration, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                Button("切换浏览器") {
                    NotificationCenter.default.post(name: .menuToggleBrowser, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
                Divider()
                Button("文档分屏模式") {
                    NotificationCenter.default.post(name: .menuToggleSplitScreen, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
                Button("专注写作模式") {
                    NotificationCenter.default.post(name: .menuFocusWriting, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                Button("进入全屏") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }

            // ── Window Menu ──
            CommandGroup(replacing: .windowSize) {
                Button("最小化") {
                    NSApp.keyWindow?.miniaturize(nil)
                }
                .keyboardShortcut("m", modifiers: .command)
                Button("缩放") {
                    NSApp.keyWindow?.zoom(nil)
                }
            }

            // ── Help Menu ──
            CommandGroup(replacing: .help) {
                Button("YunPat-Ai 帮助") {
                    if let url = URL(string: "https://github.com/yunpat/yunpat-ai") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        Settings {
            SettingsTabView(modelRouter: appState.modelRouter)
                .frame(width: PanelWidth.settingsWidth, height: PanelWidth.settingsHeight)
        }
    }
}

// MARK: - Settings Tab View (统一设置入口)

struct SettingsTabView: View {
    let modelRouter: ModelRouter
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ProviderSettingsView(modelRouter: modelRouter)
                .tabItem { Label("接口", systemImage: "key") }
                .tag(0)
            SkillSettingsView()
                .tabItem { Label("技能", systemImage: "wand.and.stars") }
                .tag(1)
            PluginSettingsView()
                .tabItem { Label("插件", systemImage: "puzzlepiece.extension") }
                .tag(2)
            MCPSettingsView()
                .tabItem { Label("MCP", systemImage: "server.rack") }
                .tag(3)
            KnowledgeSettingsView()
                .tabItem { Label("知识库", systemImage: "books.vertical") }
                .tag(4)
            RoutingSettingsView()
                .tabItem { Label("路由", systemImage: "chart.pie") }
                .tag(5)
        }
        .padding(.top, Spacing.sm)
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsTab)) { note in
            if let idx = note.object as? Int, (0...5).contains(idx) {
                selectedTab = idx
            }
            openSettingsWindow()
        }
    }

    private func openSettingsWindow() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
    let modelRouter: ModelRouter

    init() {
        let router: ModelRouter = ModelRouter()
        self.modelRouter = router
        let store: CredentialStore = CredentialStore.shared
        if let key = store.apiKey(for: .openai), !key.isEmpty {
            Task { await router.register(OpenAIProvider(apiKey: key)) }
        }
        if let key = store.apiKey(for: .anthropic), !key.isEmpty {
            Task { await router.register(AnthropicProvider(apiKey: key)) }
        }
        if let key = store.apiKey(for: .deepseek), !key.isEmpty {
            guard let deepseekURL = URL(string: "https://api.deepseek.com/v1") else { return }
            Task { await router.register(OpenAICompatProvider(apiKey: key, baseURL: deepseekURL, provider: .deepseek)) }
        }
        if let key = store.apiKey(for: .glm), !key.isEmpty {
            guard let glmURL = URL(string: "https://open.bigmodel.cn/api/paas/v4") else { return }
            Task { await router.register(OpenAICompatProvider(apiKey: key, baseURL: glmURL, provider: .glm)) }
        }

        Task {
            let converger: StorageConverger = StorageConverger.shared
            let fvEnabled: Bool = await converger.checkFileVaultStatus()
            if !fvEnabled { print("[Storage] FileVault is OFF") }
        }

        AXorcistBridge.register()

        Task {
            let consolidator: MemoryConsolidator = MemoryConsolidator.shared
            while true {
                if await consolidator.shouldRun { await consolidator.run() }
                try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
            }
        }

        Task {
            if let vaultPathStr = UserDefaults.standard.string(forKey: "yunpat.vaultPath"),
               !vaultPathStr.isEmpty {
                let vaultPath = URL(filePath: vaultPathStr)
                do {
                    try await KnowledgeBaseManager.shared.configure(vaultPath: vaultPath)
                } catch {
                    print("[AppState] KnowledgeBaseManager configure failed: \(error)")
                }
            }
        }
    }
}

extension Notification.Name {
    static let menuNewTab: Notification.Name = Notification.Name("menuNewTab")
    static let menuNewCase: Notification.Name = Notification.Name("menuNewCase")
    static let menuOpenFile: Notification.Name = Notification.Name("menuOpenFile")
    static let menuSave: Notification.Name = Notification.Name("menuSave")
    static let menuUndo: Notification.Name = Notification.Name("menuUndo")
    static let menuRedo: Notification.Name = Notification.Name("menuRedo")
    static let menuToggleSidebar: Notification.Name = Notification.Name("menuToggleSidebar")
    static let menuToggleCollaboration: Notification.Name = Notification.Name("menuToggleCollaboration")
    static let menuToggleBrowser: Notification.Name = Notification.Name("menuToggleBrowser")
    static let menuToggleSplitScreen: Notification.Name = Notification.Name("menuToggleSplitScreen")
    static let menuFocusWriting: Notification.Name = Notification.Name("menuFocusWriting")
    static let dropFile: Notification.Name = Notification.Name("dropFile")
    /// 打开设置页到指定 Tab (object: Int — 0=接口, 1=技能, 2=插件, 3=MCP, 4=知识库, 5=路由)
    static let openSettingsTab: Notification.Name = Notification.Name("openSettingsTab")
}
