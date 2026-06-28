import SwiftUI

/// 底部工具栏：📎文件 🌐浏览器 📁目录 📄分屏 💾保存 ↻同步
struct BottomToolbar: View {
    @Binding var filePickerOpen: Bool
    @Binding var browserVisible: Bool
    @Binding var folderTreeVisible: Bool
    @Binding var documentSplit: Bool

    var onSave: () -> Void
    var onSync: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ToolbarButton(icon: "paperclip", help: "打开文件", action: { filePickerOpen = true })
            ToolbarButton(icon: "safari", help: "专利浏览器", action: { browserVisible.toggle() })
                .foregroundStyle(browserVisible ? .blue : .secondary)
            ToolbarButton(icon: "folder", help: "工作目录", action: { folderTreeVisible.toggle() })
                .foregroundStyle(folderTreeVisible ? .blue : .secondary)
            ToolbarButton(icon: "doc.plaintext", help: "文档分屏", action: { documentSplit.toggle() })
                .foregroundStyle(documentSplit ? .blue : .secondary)

            Divider()
                .frame(height: 16)

            ToolbarButton(icon: "square.and.arrow.down", help: "保存", action: onSave)
            ToolbarButton(icon: "arrow.triangle.2.circlepath", help: "同步至 Agent", action: onSync)

            Spacer()

            // 状态指示
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.green)
            Text("已连接")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.thickMaterial)
    }
}

struct ToolbarButton: View {
    let icon: String
    let help: String
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .help(help)
        .scaleEffect(isHovered ? 1.15 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}
