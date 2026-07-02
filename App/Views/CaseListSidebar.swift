import SwiftUI
import YunPatCore

/// 侧栏：案件列表 + 分类筛选
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
            // 顶栏标题
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.blue)
                Text("案件列表")
                    .font(.headline)
                Spacer()
                Menu {
                    Button {
                        Task { @MainActor in
                            tabManager.addTab(title: "新案件", type: TabType.patent, flow: AgentFlow.fullAgent)
                        }
                    } label: {
                        Label("新建案件", systemImage: "doc.badge.plus")
                    }
                    Button {
                        Task { @MainActor in
                            tabManager.addTab(title: "新对话", type: TabType.general, flow: AgentFlow.copilot)
                        }
                    } label: {
                        Label("新建对话", systemImage: "bubble.left")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            // 分类筛选
            Picker("", selection: $filterCategory) {
                ForEach(CaseFilter.allCases, id: \.self) { flag in
                    Text(flag.rawValue).tag(flag)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()

            // 案件/标签列表
            List(selection: $tabManager.activeTabID) {
                ForEach(filteredTabs) { tab in
                    CaseRow(tab: tab)
                        .tag(tab.id)
                        .contextMenu {
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
            }
            .listStyle(.sidebar)

            Spacer()

            Divider()
            // 底部操作
            HStack {
                Text("共 \(tabManager.tabs.count) 个标签")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                if !tabManager.archivedTabs.isEmpty {
                    Text("\(tabManager.archivedTabs.count) 归档")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)
        }
        .background(.thickMaterial)
    }
}

/// 单个案件/标签行
struct CaseRow: View {
    let tab: ChatTab

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.typeIcon)
                .font(.caption)
                .foregroundStyle(tab.type == .patent ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .lineLimit(1)
                    .font(.system(size: 12))
                if let caseId = tab.caseId {
                    Text(caseId)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(tab.flowLabel)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
    }
}
