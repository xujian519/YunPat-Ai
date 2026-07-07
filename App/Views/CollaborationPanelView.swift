import SwiftUI
import YunPatCore

/// 人机协作审批面板 — 展示 Agent 的待确认检查点与消息中标记 "需要确认" / "⚠️" 的内容。
///
/// **注意**: 这不是多用户实时协作面板。它是一个单用户审批队列，用于展示 Agent 在工作流
/// 中需要用户确认的决策点和检查点。真正的多用户协作（CRDT/OT/WebSocket）不在当前范围内。
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
