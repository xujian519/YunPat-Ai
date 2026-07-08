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

    func openFolderAsProject(url: URL) {
        let title: String = url.lastPathComponent
        let caseId: String = title
        var tab = ChatTab(title: title, type: .patent, flow: .fullAgent)
        tab.caseId = caseId
        tab.workspacePath = url
        tabs.append(tab)
        activeTabID = tab.id
        AppStateStore.shared.showFileExplorer()
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        if let tab = tabs.first(where: { $0.id == id }) {
            var archived: ChatTab = tab
            archived.sessionMemory = SessionMemory(tabId: id)  // 清空记忆
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
            let lastIdx = tabs[index].messages.indices.last
        else { return }
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
                    onSelect: {
                        AppHaptic.alignment()
                        tabManager.activeTabID = tab.id
                    },
                    onClose: { Task { @MainActor in tabManager.closeTab(tab.id) } }
                )
            }
            Button(action: { Task { @MainActor in tabManager.addTab() } }, label: {
                Image(systemName: "plus").font(.caption)
            })
            .buttonStyle(.borderless)
            .padding(.horizontal, Spacing.xs)
            .help("新建标签 (⌘T)")
            .accessibilityLabel("新建标签")
            .accessibilityHint("创建新对话标签页")
        }
    }
}

struct TabButton: View {
    let tab: ChatTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.xxs) {
                tabIconView
                Text(tab.title)
                    .font(FontStyle.callout)
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(1)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(FontStyle.caption2)
                        .fontWeight(.bold)
                }
                .buttonStyle(.borderless)
                .help("关闭标签")
                .accessibilityLabel("关闭标签 \(tab.title)")
                .accessibilityHint("关闭当前标签页")
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .frame(minHeight: HitTarget.minimum)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(CornerRadius.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .accessibilityValue(isActive ? "活跃" : "未活跃")
    }

    @ViewBuilder
    private var tabIconView: some View {
        if case .running = tab.loopState {
            Image(systemName: "circle.circle")
                .font(.system(size: IconSize.caption))
                .foregroundStyle(Color.statusRunning)
                .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
        } else {
            Image(systemName: tab.typeIcon)
                .font(.system(size: IconSize.caption))
                .foregroundStyle(tab.type == .patent ? .blue : .secondary)
        }
    }
}
