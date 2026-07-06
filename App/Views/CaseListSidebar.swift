import SwiftUI
import YunPatCore

struct CaseListSidebar: View {
    @ObservedObject var tabManager: TabManager
    @State private var filterCategory: CaseFilter = .all

    enum CaseFilter: String, CaseIterable {
        case all = "全部"
        case patent = "案件"
        case general = "通用"
        case archived = "归档"
    }

    private var filteredTabs: [ChatTab] {
        switch filterCategory {
        case .all: return tabManager.tabs
        case .patent: return tabManager.tabs.filter { $0.type == .patent }
        case .general: return tabManager.tabs.filter { $0.type == .general }
        case .archived: return tabManager.archivedTabs
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterPicker
            Divider()
            tabList
            Spacer()
            footer
        }
        .background(.thickMaterial)
    }

    private var header: some View {
        HStack {
            Image(systemName: "folder")
                .foregroundStyle(Color.accentColor)
            Text("案件列表")
                .font(FontStyle.headline)
            Spacer()
            Menu {
                Button {
                    Task { @MainActor in
                        tabManager.addTab(
                            title: "新案件",
                            type: TabType.patent,
                            flow: AgentFlow.fullAgent
                        )
                    }
                } label: {
                    Label("新建案件", systemImage: "doc.badge.plus")
                }
                Button {
                    Task { @MainActor in
                        tabManager.addTab(
                            title: "新对话",
                            type: TabType.general,
                            flow: AgentFlow.copilot
                        )
                    }
                } label: {
                    Label("新建对话", systemImage: "bubble.left")
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新建")
            .accessibilityHint("创建新案件或新对话")
        }
        .padding()
    }

    private var filterPicker: some View {
        Picker("筛选分类", selection: $filterCategory) {
            ForEach(CaseFilter.allCases, id: \.self) { flag in
                Text(flag.rawValue).tag(flag)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("案件筛选")
        .accessibilityValue(filterCategory.rawValue)
        .padding(.horizontal)
    }

    private var tabList: some View {
        Group {
            if filteredTabs.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: filterCategory == .archived ? "暂无归档" : "无会话",
                    subtitle: filterCategory == .archived
                        ? "归档的案件将显示在这里"
                        : "点击上方 + 创建新案件或新对话",
                    action: nil
                )
                .padding(.top, Spacing.lg)
            } else {
                List(selection: $tabManager.activeTabID) {
                    ForEach(filteredTabs) { tab in
                        TabRow(tab: tab)
                            .tag(tab.id)
                            .contextMenu { contextMenuItems(for: tab) }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    @ViewBuilder
    private func contextMenuItems(for tab: ChatTab) -> some View {
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

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("共 \(tabManager.tabs.count) 个会话")
                    .font(FontStyle.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("共 \(tabManager.tabs.count) 个会话")
                Spacer()
                if !tabManager.archivedTabs.isEmpty {
                    Text("\(tabManager.archivedTabs.count) 归档")
                        .font(FontStyle.caption)
                        .foregroundStyle(Color.statusWarning)
                }
            }
            .padding(Spacing.xs)
        }
    }
}

struct TabRow: View {
    let tab: ChatTab

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            tabIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .lineLimit(1)
                    .font(FontStyle.callout)
                if let caseId = tab.caseId {
                    Text(caseId)
                        .font(FontStyle.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            flowBadge
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(buildAccessibilityLabel())
    }

    @ViewBuilder
    private var tabIcon: some View {
        if case .running = tab.loopState {
            Image(systemName: "circle.circle")
                .font(.system(size: IconSize.caption))
                .foregroundStyle(Color.statusRunning)
                .symbolEffect(.pulse, options: .repeating)
        } else {
            Image(systemName: tab.typeIcon)
                .font(.system(size: IconSize.caption))
                .foregroundStyle(tab.type == .patent ? .blue : .secondary)
        }
    }

    private var flowBadge: some View {
        Text(tab.flowLabel)
            .font(FontStyle.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.xxs)
            .padding(.vertical, 2)
            .background(Color.appStatusNeutralSoft)
            .cornerRadius(CornerRadius.sm)
    }

    private func buildAccessibilityLabel() -> String {
        var label: String = tab.title
        if let caseId = tab.caseId {
            label += ", 案件号: \(caseId)"
        }
        if case .running = tab.loopState {
            label += ", 正在运行"
        }
        return label
    }
}
