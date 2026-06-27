import SwiftUI
import AppKit
import YunPatNetworking

@main
struct YunPatApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(router: appState.modelRouter)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About YunPat-Ai") {
                    NSApp.orderFrontStandardAboutPanel(options: [:])
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    NotificationCenter.default.post(name: .menuNewTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
        Settings {
            ProviderSettingsView()
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    let modelRouter: ModelRouter

    init() {
        let router = ModelRouter()
        let store = CredentialStore.shared
        if let key = store.apiKey(for: .openai), !key.isEmpty {
            Task { await router.register(OpenAIProvider(apiKey: key)) }
        }
        if let key = store.apiKey(for: .anthropic), !key.isEmpty {
            Task { await router.register(AnthropicProvider(apiKey: key)) }
        }
        if let key = store.apiKey(for: .deepseek), !key.isEmpty {
            Task { await router.register(OpenAICompatProvider(apiKey: key, baseURL: URL(string: "https://api.deepseek.com/v1")!, provider: .deepseek)) }
        }
        if let key = store.apiKey(for: .glm), !key.isEmpty {
            Task { await router.register(OpenAICompatProvider(apiKey: key, baseURL: URL(string: "https://open.bigmodel.cn/api/paas/v4")!, provider: .glm)) }
        }
        self.modelRouter = router
    }
}

extension Notification.Name {
    static let menuNewTab = Notification.Name("menuNewTab")
}
