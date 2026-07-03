import SwiftUI

struct MCPSettingsView: View {
    @State private var servers: [MCPServerConfig] = [
        MCPServerConfig(name: "Playwright", command: "npx", args: "@playwright/mcp", enabled: true)
    ]
    @State private var showAddSheet: Bool = false

    struct MCPServerConfig: Identifiable {
        let id = UUID()
        var name: String
        var command: String
        var args: String
        var enabled: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MCP 服务器")
                .font(FontStyle.headline)
                .padding(.horizontal)
                .padding(.top, Spacing.sm)

            Text("MCP (Model Context Protocol) 服务器为 Agent 提供外部工具和上下文。")
                .font(FontStyle.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, Spacing.xxs)

            if servers.isEmpty {
                emptyState
            } else {
                List {
                    ForEach($servers) { $server in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                    .font(FontStyle.callout)
                                Text("\(server.command) \(server.args)")
                                    .font(FontStyle.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            HStack(spacing: Spacing.xs) {
                                Circle()
                                    .fill(server.enabled ? Color.statusSuccess : Color.secondary)
                                    .frame(width: 6, height: 6)
                                Text(server.enabled ? "运行中" : "已暂停")
                                    .font(FontStyle.caption2)
                                    .foregroundStyle(.secondary)
                                Toggle("", isOn: $server.enabled)
                                    .accessibilityLabel("\(server.name) \(server.enabled ? "已启用" : "已停用")")
                            }
                        }
                        .padding(.vertical, Spacing.xxs)
                    }
                    .onDelete { indexSet in
                        servers.remove(atOffsets: indexSet)
                    }
                }
                .listStyle(.inset)
            }

            Spacer()

            Divider()
            HStack {
                Button("添加 MCP 服务器…") {
                    showAddSheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("添加 MCP 服务器")

                Spacer()

                Button("刷新状态") {
                    refreshServers()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("刷新 MCP 服务器状态")
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 300)
        .sheet(isPresented: $showAddSheet) {
            addServerSheet
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("未配置 MCP 服务器")
                .font(FontStyle.headline)
                .foregroundStyle(.secondary)
            Text("MCP 服务器扩展 Agent 的能力，例如提供浏览器自动化、\n数据库查询、文件系统访问等工具。")
                .font(FontStyle.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("未配置 MCP 服务器，点击添加按钮开始配置")
    }

    private var addServerSheet: some View {
        VStack(spacing: Spacing.sm) {
            Text("添加 MCP 服务器")
                .font(FontStyle.headline)
                .padding(.top)

            Form {
                TextField("名称", text: .constant(""))
                TextField("命令", text: .constant(""))
                TextField("参数", text: .constant(""))
            }
            .padding(.horizontal)

            HStack {
                Button("取消") { showAddSheet = false }
                    .buttonStyle(.bordered)
                Button("添加") {
                    showAddSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom)
        }
        .frame(width: 360, height: 260)
    }

    private func refreshServers() {}
}
