import SwiftUI

struct PluginSettingsView: View {
    @State private var plugins: [PluginInfo] = []
    @State private var isLoading: Bool = false

    struct PluginInfo: Identifiable {
        let id = UUID()
        let name: String
        let version: String
        let enabled: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("已安装插件")
                .font(FontStyle.headline)
                .padding(.horizontal)
                .padding(.top, Spacing.sm)

            if plugins.isEmpty {
                emptyState
            } else {
                List(plugins) { plugin in
                    HStack {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plugin.name)
                                .font(FontStyle.callout)
                            Text("版本 \(plugin.version)")
                                .font(FontStyle.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: .constant(plugin.enabled))
                            .accessibilityLabel("\(plugin.name) \(plugin.enabled ? "已启用" : "已停用")")
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                .listStyle(.inset)
            }

            Spacer()

            Divider()
            HStack {
                Button("安装插件…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".agents/skills")
                    panel.message = "选择包含 Plugin.swift 的插件目录"
                    panel.runModal()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("从文件夹安装插件")
                .accessibilityHint("选择包含插件配置文件的目录")

                Spacer()

                if !plugins.isEmpty {
                    Button("刷新") {
                        refreshPlugins()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("刷新插件列表")
                }
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear { refreshPlugins() }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("暂无插件")
                .font(FontStyle.headline)
                .foregroundStyle(.secondary)
            Text("插件为 Agent 提供可注册的自定义工具和 MCP 服务器。\n从本地文件夹安装或从社区下载。")
                .font(FontStyle.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("暂无已安装插件")
    }

    private func refreshPlugins() {
        isLoading = true
        defer { isLoading = false }
        let knownDirs: [URL] = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode/skills"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills")
        ]
        var discovered: [PluginInfo] = []
        for dir in knownDirs where FileManager.default.fileExists(atPath: dir.path) {
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) {
                for item in contents {
                    let isDir: Bool = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if isDir {
                        let pluginName: String = item.lastPathComponent
                        discovered.append(PluginInfo(
                            name: pluginName, version: "1.0", enabled: true
                        ))
                    }
                }
            }
        }
        plugins = discovered
    }
}
