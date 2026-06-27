import SwiftUI

struct PluginSettingsView: View {
    var body: some View {
        VStack {
            Text("已安装插件")
                .font(.headline)
            Text("暂无插件")
                .foregroundStyle(.secondary)
            Button("安装插件…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.runModal()
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 200)
    }
}
