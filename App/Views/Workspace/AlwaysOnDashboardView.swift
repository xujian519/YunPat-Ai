import SwiftUI
import YunPatCore

/// PilotDeck 风格常驻 Dashboard
struct AlwaysOnDashboardView: View {
    @StateObject private var manager = AlwaysOnManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                PageHeader(
                    title: "Always-On 仪表盘",
                    subtitle: "所有工作区的活动动态。",
                    actions: {
                        Button(
                            action: {},
                            label: {
                                HStack(spacing: Spacing.xxs) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: IconSize.inlineSmall))
                                    Text("刷新")
                                        .font(FontStyle.callout)
                                }
                            }
                        )
                        .buttonStyle(.plain)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.appSurfacePrimary)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .stroke(Color.appSeparator.opacity(0.5), lineWidth: BorderWidth.hairline)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                    }
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: Spacing.md) {
                    StatCard(
                        title: "今日事件",
                        value: "0",
                        icon: "calendar",
                        trend: "待处理",
                        color: .blue
                    )
                    StatCard(
                        title: "活跃项目",
                        value: "0",
                        icon: "folder.badge.person.crop",
                        trend: "监控中",
                        color: .green
                    )
                    StatCard(
                        title: "正在运行",
                        value: "0",
                        icon: "arrow.triangle.2.circlepath",
                        trend: "常驻任务",
                        color: .orange
                    )
                }

                recentEventsSection
                taskSection
                shortcutSection
            }
            .padding(Spacing.lg)
        }
        .background(Color.appBackground)
        .task { await manager.subscribe() }
    }

    private var recentEventsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("近期事件")

            VStack(spacing: 0) {
                EmptyStateView(
                    icon: "waveform",
                    title: "",
                    subtitle: "暂无 Always-On 事件记录。",
                    action: nil
                )
                .padding(.vertical, Spacing.xl)
            }
            .appCard()
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("常驻任务")

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
        }
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("快捷动作")

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

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(FontStyle.callout)
            .fontWeight(.semibold)
            .foregroundStyle(Color.appTextSecondary)
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

#Preview {
    AlwaysOnDashboardView()
        .frame(width: 900, height: 600)
}
