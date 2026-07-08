import AppKit
import SwiftUI
import YunPatCore

/// PilotDeck 风格常驻 Dashboard
struct AlwaysOnDashboardView: View {
    @StateObject private var manager: AlwaysOnManager
    var tabManager: TabManager?
    var chatManager: ChatManager?
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared
    @State private var screenshotError: String?

    init(tabManager: TabManager? = nil, chatManager: ChatManager? = nil) {
        _manager = StateObject(wrappedValue: AlwaysOnManager())
        self.tabManager = tabManager
        self.chatManager = chatManager
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                PageHeader(
                    title: "Always-On 仪表盘",
                    subtitle: "所有工作区的活动动态。",
                    actions: {
                        Button(
                            action: { Task { await manager.refreshStats() } },
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
                        title: "剪贴板事件",
                        value: "\(manager.clipboardCount)",
                        icon: "doc.on.clipboard",
                        trend: "已记录",
                        color: .blue
                    )
                    StatCard(
                        title: "活跃任务",
                        value: "\(manager.runningCount)",
                        icon: "arrow.triangle.2.circlepath",
                        trend: "运行中",
                        color: .green
                    )
                    StatCard(
                        title: "总任务数",
                        value: "\(AlwaysOnTaskKind.allCases.count)",
                        icon: "list.bullet",
                        trend: "已配置",
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

            if manager.clipboardItems.isEmpty {
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
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(Array(manager.clipboardItems.prefix(8).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: IconSize.caption))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(item.prefix(80)))
                                    .font(FontStyle.callout)
                                    .lineLimit(2)
                                Text("剪贴板")
                                    .font(FontStyle.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .appCard(cornerRadius: CornerRadius.md)
                    }
                }
            }
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
                ShortcutButton(title: "全局搜索", icon: "magnifyingglass", shortcut: "⌘⇧F") {
                    appState.switchToModule(.files)
                    appState.openRightPanel(.fileExplorer)
                }
                ShortcutButton(title: "新建速记", icon: "square.and.pencil", shortcut: "⌘⇧N") {
                    if let tabManager {
                        tabManager.addTab(title: "速记", type: .general, flow: .copilot)
                        appState.switchToModule(.agent)
                    } else {
                        NotificationCenter.default.post(name: .menuNewTab, object: nil)
                    }
                }
                ShortcutButton(title: "截图提问", icon: "camera", shortcut: "⌘⇧5") {
                    Task { await takeScreenshotAndAsk() }
                }
            }
        }
        .alert("截图失败", isPresented: .init(
            get: { screenshotError != nil },
            set: { if !$0 { screenshotError = nil } }
        )) {
            Button("确定") { screenshotError = nil }
        } message: {
            Text(screenshotError ?? "")
        }
    }

    private func takeScreenshotAndAsk() async {
        guard AXIsProcessTrusted() else {
            await MainActor.run {
                screenshotError = "需要辅助功能/屏幕录制权限才能截图。请前往系统设置 > 隐私与安全性 > 辅助功能授予权限。"
            }
            return
        }
        do {
            let bridge = AXorcistBridge()
            let data: Data = try await bridge.screenshot(app: nil, region: nil)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("yunpat_screenshot_\(UUID().uuidString).png")
            try data.write(to: tempURL)

            await MainActor.run {
                appState.switchToModule(.agent)
                if let chatManager, let tabManager, tabManager.activeTabID != nil {
                    chatManager.inputText = "请描述这张截图并据此回答我的问题。图片路径: \(tempURL.path)"
                    Task { await chatManager.sendMessage(in: tabManager) }
                } else {
                    screenshotError = "截图已保存到 \(tempURL.path)，但当前没有活跃对话。"
                }
            }
        } catch {
            await MainActor.run {
                screenshotError = error.localizedDescription
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .buttonStyle(.plain)
    }
}

@MainActor
final class AlwaysOnManager: ObservableObject {
    @Published var statuses: [AlwaysOnTaskKind: AlwaysOnTaskStatus] = [:]
    @Published var clipboardItems: [String] = []

    func subscribe() async {
        let scheduler: AlwaysOnScheduler = AlwaysOnScheduler.shared
        for kind in AlwaysOnTaskKind.allCases {
            statuses[kind] = await scheduler.status(for: kind)
        }
        await refreshStats()
        for await status in scheduler.statusStream() {
            statuses[status.kind] = status
            await refreshStats()
        }
    }

    func refreshStats() async {
        clipboardItems = await AlwaysOnScheduler.shared.recentClipboardContent()
    }

    func status(for kind: AlwaysOnTaskKind) -> AlwaysOnTaskStatus {
        statuses[kind] ?? AlwaysOnTaskStatus(kind: kind, state: .paused, lastRun: nil, nextRun: nil, errorMessage: nil)
    }

    func toggle(_ kind: AlwaysOnTaskKind) {
        Task {
            await AlwaysOnScheduler.shared.toggle(kind)
            await refreshStats()
        }
    }

    var runningCount: Int {
        statuses.values.filter {
            if case .running = $0.state { return true }
            return false
        }.count
    }

    var clipboardCount: Int {
        clipboardItems.count
    }
}

#Preview {
    AlwaysOnDashboardView()
        .frame(width: 900, height: 600)
}
