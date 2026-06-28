import SwiftUI
import YunPatCore

@MainActor
final class TabManager: ObservableObject {
    @Published var tabs: [ChatTab] = []
    @Published var archivedTabs: [ChatTab] = []
    @Published var activeTabID: UUID?

    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        let defaultTab = ChatTab(title: "新对话", type: .general)
        tabs = [defaultTab]
        activeTabID = defaultTab.id
        observer = NotificationCenter.default.addObserver(
            forName: .menuNewTab, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.addTab() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func addTab(title: String = "新对话", type: TabType = .general, flow: AgentFlow = .copilot) {
        let newTab = ChatTab(title: title, type: type, flow: flow)
        tabs.append(newTab)
        activeTabID = newTab.id
    }

    func addPatentCase(title: String, caseId: String) {
        var tab = ChatTab(title: title, type: .patent, flow: .fullAgent)
        tab.caseId = caseId
        tabs.append(tab)
        activeTabID = tab.id
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        if let tab = tabs.first(where: { $0.id == id }) {
            var archived = tab
            archived.sessionMemory = SessionMemory(tabId: id) // 清空记忆
            archivedTabs.insert(archived, at: 0)
        }
        tabs.removeAll { $0.id == id }
        if activeTabID == id { activeTabID = tabs.first?.id }
    }

    func archiveTab(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        archivedTabs.insert(tabs[idx], at: 0)
        tabs.remove(at: idx)
        if activeTabID == id { activeTabID = tabs.first?.id }
    }

    func restoreTab(_ id: UUID) {
        guard let idx = archivedTabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.append(archivedTabs[idx])
        archivedTabs.remove(at: idx)
        activeTabID = id
    }

    func appendMessage(to tabID: UUID, _ message: ChatMessage) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].messages.append(message)
    }

    func appendToLastMessage(to tabID: UUID, _ delta: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              let lastIdx = tabs[index].messages.indices.last else { return }
        tabs[index].messages[lastIdx].content += delta
    }
}

struct TabBar: View {
    @ObservedObject var tabManager: TabManager

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabManager.tabs) { tab in
                TabButton(
                    tab: tab,
                    isActive: tabManager.activeTabID == tab.id,
                    onSelect: { tabManager.activeTabID = tab.id },
                    onClose: { Task { @MainActor in tabManager.closeTab(tab.id) } }
                )
            }
            Button(action: { Task { @MainActor in tabManager.addTab() } }) {
                Image(systemName: "plus").font(.caption)
            }
            .buttonStyle(.plain).padding(.horizontal, 8)
        }
    }
}

struct TabButton: View {
    let tab: ChatTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tab.typeIcon)
                .font(.system(size: 8))
                .foregroundStyle(tab.type == .patent ? .blue : .secondary)
            Text(tab.title).font(.system(size: 12, weight: isActive ? .semibold : .regular)).lineLimit(1)
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .onTapGesture { onSelect() }
    }
}
