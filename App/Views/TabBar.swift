import SwiftUI

@MainActor
final class TabManager: ObservableObject {
    @Published var tabs: [ChatTab] = []
    @Published var activeTabID: UUID?

    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        let defaultTab = ChatTab(title: "新对话")
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

    func addTab() {
        let newTab = ChatTab(title: "新对话")
        tabs.append(newTab)
        activeTabID = newTab.id
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        tabs.removeAll { $0.id == id }
        if activeTabID == id { activeTabID = tabs.first?.id }
    }

    func appendMessage(to tabID: UUID, _ message: ChatMessage) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].messages.append(message)
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
                    onClose: { tabManager.closeTab(tab.id) }
                )
            }
            Button(action: { tabManager.addTab() }) {
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
            Text(tab.title).font(.system(size: 12, weight: isActive ? .semibold : .regular)).lineLimit(1)
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .onTapGesture { onSelect() }
    }
}
