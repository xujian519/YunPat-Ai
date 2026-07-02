import SwiftUI

struct KnowledgeSettingsView: View {
    @State private var vaultPath: String = ""
    @State private var vaultStatus: String = "未配置"

    var body: some View {
        Form {
            Section("知识库（宝宸知识库）") {
                HStack {
                    TextField("Obsidian Vault 路径", text: $vaultPath)
                    Button("浏览") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK { vaultPath = panel.url?.path ?? "" }
                    }
                }
                Text("状态：\(vaultStatus)").font(.caption).foregroundStyle(.secondary)
                Button("验证") {
                    let url = URL(filePath: vaultPath)
                    if FileManager.default.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path),
                        FileManager.default.fileExists(atPath: url.appendingPathComponent("Wiki/专利实务").path) {
                        vaultStatus = "✅ 有效"
                        UserDefaults.standard.set(vaultPath, forKey: "yunpat.vaultPath")
                    } else {
                        vaultStatus = "❌ 无效"
                    }
                }
            }
        }
        .padding().frame(minWidth: 400, minHeight: 200)
        .onAppear { vaultPath = UserDefaults.standard.string(forKey: "yunpat.vaultPath") ?? defaultVaultPath() }
    }

    private func defaultVaultPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Mobile Documents/iCloud~md~obsidian/Documents/宝宸知识库"
        ).path
    }
}
