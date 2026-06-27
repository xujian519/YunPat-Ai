import SwiftUI

struct MCPSettingsView: View {
    struct Server: Identifiable { let id = UUID(); let name: String; let command: String; let args: String }
    @State private var servers: [Server] = [
        Server(name: "Playwright", command: "npx", args: "@playwright/mcp"),
    ]

    var body: some View {
        List {
            ForEach(servers) { s in
                VStack(alignment: .leading) {
                    Text(s.name).font(.headline)
                    Text("\(s.command) \(s.args)").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack { Spacer(); Button("添加 MCP 服务器…") {}; Spacer() }
        }
        .frame(minWidth: 400, minHeight: 200)
    }
}
