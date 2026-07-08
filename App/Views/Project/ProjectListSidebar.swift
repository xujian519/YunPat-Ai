import AppKit
import SwiftUI
import YunPatCore

/// PilotDeck 风格项目列表面板
struct ProjectListSidebar: View {
    @ObservedObject var tabManager: TabManager
    @State private var selectedScope: SidebarScope = .projects
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    enum SidebarScope: String, CaseIterable {
        case projects = "项目"
        case general = "通用"
    }

    private var visibleTabs: [ChatTab] {
        switch selectedScope {
        case .projects:
            return tabManager.tabs.filter { $0.type == .patent }
        case .general:
            return tabManager.tabs.filter { $0.type == .general }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            logoHeader
            scopeSwitcher
            projectTreeHeader
            Divider()
            tabList
            Spacer()
            settingsButton
        }
        .background(Color.appSidebarBackground)
    }

    // MARK: - Logo Header

    private var logoHeader: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "square.fill.text.grid.1x2")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("YUNPAT-AI")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Color.appTextPrimary)
            Spacer()
            Button(
                action: {},
                label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: IconSize.sidebar, weight: .medium))
                        .foregroundStyle(Color.appTextSecondary)
                }
            )
            .buttonStyle(.plain)
            .help("应用启动器")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Scope Switcher

    private var scopeSwitcher: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(SidebarScope.allCases, id: \.self) { scope in
                Button {
                    withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
                        selectedScope = scope
                    }
                } label: {
                    Text(scope.rawValue)
                        .font(FontStyle.callout)
                        .fontWeight(selectedScope == scope ? .semibold : .regular)
                        .foregroundStyle(selectedScope == scope ? Color.appTextPrimary : Color.appTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(selectedScope == scope ? Color.appSurfacePrimary : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .stroke(
                                    Color.appSeparator.opacity(0.5),
                                    lineWidth: selectedScope == scope ? 0 : BorderWidth.hairline)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
    }

    // MARK: - Project Tree Header

    private var projectTreeHeader: some View {
        HStack(spacing: 0) {
            Text(selectedScope == .projects ? "项目" : "通用")
                .font(FontStyle.caption)
                .foregroundStyle(Color.appTextTertiary)
                .textCase(.uppercase)
            Spacer()
            HStack(spacing: Spacing.xxs) {
                Button {
                    Task { @MainActor in
                        tabManager.addTab(
                            title: selectedScope == .projects ? "新案件" : "新对话",
                            type: selectedScope == .projects ? .patent : .general,
                            flow: selectedScope == .projects ? .fullAgent : .copilot
                        )
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: IconSize.caption, weight: .bold))
                        .foregroundStyle(Color.appTextSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建")

                Button {
                    openFolderAsProject()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: IconSize.caption, weight: .medium))
                        .foregroundStyle(Color.appTextSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开文件夹")
                .accessibilityHint("选择文件夹作为新项目")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Tab List

    private var tabList: some View {
        Group {
            if visibleTabs.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: selectedScope == .projects ? "无项目" : "无对话",
                    subtitle: "点击上方 + 创建",
                    action: nil
                )
                .padding(.top, Spacing.lg)
            } else {
                List(selection: $tabManager.activeTabID) {
                    ForEach(groupedTabs.keys.sorted(), id: \.self) { group in
                        if let tabs = groupedTabs[group] {
                            SidebarGroupRow(
                                group: group,
                                tabs: tabs,
                                tabManager: tabManager
                            )
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var groupedTabs: [String: [ChatTab]] {
        let grouped = Dictionary(grouping: visibleTabs) { tab in
            if let caseId = tab.caseId {
                return caseId
            }
            return tab.type == .patent ? "未分组项目" : "通用对话"
        }
        return grouped
    }

    private func openFolderAsProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择项目文件夹"
        panel.message = "选择一个文件夹作为新项目的工作目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            tabManager.openFolderAsProject(url: url)
        }
    }

    // MARK: - Settings Button

    private var settingsButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                NotificationCenter.default.post(name: .openSettingsTab, object: 0)
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "gearshape")
                        .font(.system(size: IconSize.sidebar, weight: .medium))
                        .foregroundStyle(Color.appTextSecondary)
                    Text("设置")
                        .font(FontStyle.callout)
                        .foregroundStyle(Color.appTextPrimary)
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
        }
    }
}

// MARK: - Sidebar Group Row

struct SidebarGroupRow: View {
    let group: String
    let tabs: [ChatTab]
    @ObservedObject var tabManager: TabManager
    @State private var isExpanded: Bool = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(tabs) { tab in
                SidebarTabRow(tab: tab, tabManager: tabManager)
                    .tag(tab.id)
            }
        } label: {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: tabs.first?.typeIcon ?? "folder")
                    .font(.system(size: IconSize.caption))
                    .foregroundStyle(.secondary)
                Text(group)
                    .font(FontStyle.callout)
                    .lineLimit(1)
                Spacer()
                if tabs.count > 1 {
                    Text("\(tabs.count)")
                        .font(FontStyle.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .tint(Color.appTextSecondary)
    }
}

// MARK: - Sidebar Tab Row

struct SidebarTabRow: View {
    let tab: ChatTab
    @ObservedObject var tabManager: TabManager
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    @State private var isHovered: Bool = false

    private var isActive: Bool {
        tabManager.activeTabID == tab.id
    }

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .lineLimit(1)
                    .font(FontStyle.callout)
                if let time = relativeTime {
                    Text(time)
                        .font(FontStyle.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.leading, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(
                    isActive
                        ? Color.appSurfaceSecondary : (isHovered ? Color.appSurfaceTertiary.opacity(0.5) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            tabManager.activeTabID = tab.id
            if tab.type == .patent {
                appState.showFileExplorer()
            }
        }
        .contextMenu { contextMenuItems }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    private var dotColor: Color {
        if case .running = tab.loopState {
            return Color.statusRunning
        }
        return isActive ? Color.accentColor : Color.appTextTertiary
    }

    private var relativeTime: String? {
        // 实际项目中可替换为真实时间戳
        nil
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if tab.type == .patent {
            Button {
                Task { @MainActor in tabManager.archiveTab(tab.id) }
            } label: {
                Label("归档", systemImage: "archivebox")
            }
        }
        Button(role: .destructive) {
            Task { @MainActor in tabManager.closeTab(tab.id) }
        } label: {
            Label("关闭", systemImage: "xmark")
        }
    }
}

#Preview {
    ProjectListSidebar(tabManager: TabManager())
        .frame(width: 260, height: 600)
}
