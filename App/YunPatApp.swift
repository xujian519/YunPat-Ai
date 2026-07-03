import AppKit
import SwiftUI
import YunPatCore
import YunPatNetworking

@main
struct YunPatApp: App {
    @StateObject private var appState: AppState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(router: appState.modelRouter)
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
        .windowResizability(.contentSize)
        .commands {
            // ── App Info ──
            CommandGroup(replacing: .appInfo) {
                Button("关于 YunPat-Ai") { NSApp.orderFrontStandardAboutPanel(options: [:]) }
            }

            // ── File Menu ──
            CommandGroup(replacing: .newItem) {
                Button("新建标签") { NotificationCenter.default.post(name: .menuNewTab, object: nil) }
                    .keyboardShortcut("t", modifiers: .command)
                Button("新建案件") { NotificationCenter.default.post(name: .menuNewCase, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("打开文件…") { NotificationCenter.default.post(name: .menuOpenFile, object: nil) }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("保存当前文档") { NotificationCenter.default.post(name: .menuSave, object: nil) }
                    .keyboardShortcut("s", modifiers: .command)
            }

            // ── Edit Menu ──
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { NotificationCenter.default.post(name: .menuUndo, object: nil) }
                    .keyboardShortcut("z", modifiers: .command)
                Button("重做") { NotificationCenter.default.post(name: .menuRedo, object: nil) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            // ── View Menu ──
            CommandMenu("显示") {
                Button("切换侧栏") { NotificationCenter.default.post(name: .menuToggleSidebar, object: nil) }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Button("切换协作面板") { NotificationCenter.default.post(name: .menuToggleCollaboration, object: nil) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Button("切换浏览器") { NotificationCenter.default.post(name: .menuToggleBrowser, object: nil) }
                    .keyboardShortcut("b", modifiers: [.command, .option])
                Divider()
                Button("文档分屏模式") { NotificationCenter.default.post(name: .menuToggleSplitScreen, object: nil) }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                Button("进入全屏") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
        }
        Settings {
            TabView {
                ProviderSettingsView(modelRouter: appState.modelRouter)
                    .tabItem { Label("接口", systemImage: "key") }
                SkillSettingsView()
                    .tabItem { Label("技能", systemImage: "wand.and.stars") }
                PluginSettingsView()
                    .tabItem { Label("插件", systemImage: "puzzlepiece.extension") }
                MCPSettingsView()
                    .tabItem { Label("MCP", systemImage: "server.rack") }
                KnowledgeSettingsView()
                    .tabItem { Label("知识库", systemImage: "books.vertical") }
            }
        }
    }
}

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
            var converger: StorageConverger = StorageConverger.shared
            let fvEnabled: Bool = await converger.checkFileVaultStatus()
            if !fvEnabled { print("[Storage] FileVault is OFF") }
        }

        Task {
            let consolidator: MemoryConsolidator = MemoryConsolidator.shared
            while true {
                if await consolidator.shouldRun { await consolidator.run() }
                try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
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
    static let dropFile: Notification.Name = Notification.Name("dropFile")
}
