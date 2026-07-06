import SwiftUI
import YunPatCore

struct AlwaysOnDashboardView: View {
    @StateObject private var manager = AlwaysOnManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: Spacing.md) {
                    ForEach(AlwaysOnTaskKind.allCases, id: \.self) { kind in
                        let status = manager.status(for: kind)
                        AlwaysOnCard(
                            title: title(for: kind),
                            subtitle: subtitle(for: status),
                            icon: icon(for: kind),
                            isActive: status.state == .running
                        ) {
                            manager.toggle(kind)
                        }
                    }
                }

                shortcutSection
            }
            .padding(Spacing.lg)
        }
        .background(Color.appBackground)
        .task { await manager.subscribe() }
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

    private func title(for kind: AlwaysOnTaskKind) -> String {
        switch kind {
        case .clipboard: return "剪贴板监听"
        case .fileWatcher: return "文件监听"
        case .periodicSummary: return "定时总结"
        case .memoryConsolidation: return "记忆整理"
        }
    }

    private func subtitle(for status: AlwaysOnTaskStatus) -> String {
        switch status.state {
        case .running:
            if let last = status.lastRun {
                let elapsed = Int(-last.timeIntervalSinceNow)
                return "运行中 · \(elapsed)s 前执行"
            }
            return "运行中"
        case .paused:
            return "已暂停"
        case .error(let msg):
            return "错误: \(msg)"
        }
    }

    private func icon(for kind: AlwaysOnTaskKind) -> String {
        switch kind {
        case .clipboard: return "doc.on.clipboard"
        case .fileWatcher: return "folder.badge.gear"
        case .periodicSummary: return "timer"
        case .memoryConsolidation: return "brain.head.profile"
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
            .appCard()
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
                .appSurface(cornerRadius: CornerRadius.sm, surface: Color.appSurfaceSecondary)
        }
        .padding()
        .frame(minWidth: 160)
        .appCard()
    }
}

@MainActor
final class AlwaysOnManager: ObservableObject {
    @Published var statuses: [AlwaysOnTaskKind: AlwaysOnTaskStatus] = [:]

    func subscribe() async {
        let scheduler: AlwaysOnScheduler = AlwaysOnScheduler.shared
        for kind in AlwaysOnTaskKind.allCases {
            statuses[kind] = await scheduler.status(for: kind)
        }
        for await status in scheduler.statusStream() {
            statuses[status.kind] = status
        }
    }

    func status(for kind: AlwaysOnTaskKind) -> AlwaysOnTaskStatus {
        statuses[kind] ?? AlwaysOnTaskStatus(kind: kind, state: .paused, lastRun: nil, nextRun: nil, errorMessage: nil)
    }

    func toggle(_ kind: AlwaysOnTaskKind) {
        Task { await AlwaysOnScheduler.shared.toggle(kind) }
    }
}
