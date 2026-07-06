import SwiftUI
import YunPatCore

/// 常驻任务 Dashboard：监听、快捷动作、后台工具
struct AlwaysOnDashboardView: View {
    @State private var isListening: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: Spacing.md) {
                    AlwaysOnCard(
                        title: "剪贴板监听",
                        subtitle: isListening ? "运行中" : "已暂停",
                        icon: "doc.on.clipboard",
                        isActive: isListening
                    ) {
                        isListening.toggle()
                    }
                    AlwaysOnCard(
                        title: "屏幕截图",
                        subtitle: "⌘⇧5 触发",
                        icon: "camera.viewfinder",
                        isActive: false
                    ) {}
                    AlwaysOnCard(
                        title: "文件监听",
                        subtitle: "工作目录",
                        icon: "folder.badge.gear",
                        isActive: true
                    ) {}
                    AlwaysOnCard(
                        title: "定时总结",
                        subtitle: "每 6 小时",
                        icon: "timer",
                        isActive: true
                    ) {}
                }

                shortcutSection
            }
            .padding(Spacing.lg)
        }
        .background(Color.appBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("常驻")
                .font(FontStyle.largeTitle)
            Text("后台常驻能力与快捷入口")
                .font(FontStyle.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("快捷动作")
                .font(FontStyle.title2)

            HStack(spacing: Spacing.md) {
                ShortcutButton(title: "全局搜索", icon: "magnifyingglass", shortcut: "⌘⇧F")
                ShortcutButton(title: "新建速记", icon: "square.and.pencil", shortcut: "⌘⇧N")
                ShortcutButton(title: "截图提问", icon: "camera", shortcut: "⌘⇧5")
            }
        }
    }
}

struct AlwaysOnCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: IconSize.messageIcon))
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    Spacer()
                    Circle()
                        .fill(isActive ? Color.statusSuccess : Color.statusWarning)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(FontStyle.headline)
                Text(subtitle)
                    .font(FontStyle.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(Color.appSurfacePrimary)
            .cornerRadius(CornerRadius.lg)
        }
        .buttonStyle(.plain)
    }
}

struct ShortcutButton: View {
    let title: String
    let icon: String
    let shortcut: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(FontStyle.callout)
            Spacer()
            Text(shortcut)
                .font(FontStyle.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 2)
                .background(Color.appSurfaceSecondary)
                .cornerRadius(CornerRadius.sm)
        }
        .padding()
        .frame(minWidth: 160)
        .background(Color.appSurfacePrimary)
        .cornerRadius(CornerRadius.lg)
    }
}

#Preview {
    AlwaysOnDashboardView()
        .frame(width: 900, height: 600)
}
