import SwiftUI
import YunPatCore

struct CollaborationPanel: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var chatManager: ChatManager

    private func pendingApprovals() -> [ApprovalItem] {
        guard let activeID = tabManager.activeTabID,
            let tab = tabManager.tabs.first(where: { $0.id == activeID })
        else { return [] }
        var items: [ApprovalItem] = []
        if case .waitingApproval(let req) = tab.loopState {
            items.append(
                ApprovalItem(
                    title: "等待确认",
                    detail: req.detail,
                    checkpoint: tab.loopStateDescription
                ))
        }
        for msg in tab.messages {
            if msg.content.contains("需要确认") || msg.content.contains("⚠️") {
                items.append(ApprovalItem(title: "待确认", detail: msg.content, checkpoint: nil))
            }
        }
        return items
    }

    var body: some View {
        let approvals: [ApprovalItem] = pendingApprovals()
        return VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "checklist")
                    .font(.title2)
                Text("协作")
                    .font(FontStyle.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal)

            if approvals.isEmpty {
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("无待确认事项")
                        .font(FontStyle.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
                .accessibilityLabel("无待确认事项")
            } else {
                List {
                    ForEach(approvals) { item in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            if let checkpoint = item.checkpoint {
                                Text(checkpoint)
                                    .font(FontStyle.caption2)
                                    .foregroundStyle(Color.accentColor)
                            }
                            Text(item.title)
                                .font(FontStyle.caption)
                                .foregroundStyle(Color.statusWarning)
                            Text(item.detail)
                                .font(FontStyle.caption)
                                .lineLimit(4)
                        }
                        .padding(Spacing.xxs)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackgroundColor)
    }
}

struct ApprovalItem: Identifiable, Sendable {
    let id: UUID = UUID()
    let title: String
    let detail: String
    let checkpoint: String?
}
