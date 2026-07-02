import SwiftUI

struct CollaborationPanel: View {
    @Binding var pendingApprovals: [ApprovalItem]
    @Binding var completedItems: [ApprovalItem]

    var body: some View {
        VStack(spacing: 12) {
            if !pendingApprovals.isEmpty {
                Section {
                    Label("待确认 (\(pendingApprovals.count))", systemImage: "clock").font(.headline).foregroundStyle(
                        .orange)
                    ForEach(pendingApprovals) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title).font(.headline)
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("确认") { completeApproval(item, approved: true) }.buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                Button("拒绝") { completeApproval(item, approved: false) }.buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }.padding().background(Color.secondary.opacity(0.05)).cornerRadius(8)
                    }
                }
            }
            if !completedItems.isEmpty {
                Section {
                    Label("已完成 (\(completedItems.count))", systemImage: "checkmark.circle").font(.headline)
                        .foregroundStyle(.green)
                }
            }
            if pendingApprovals.isEmpty && completedItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checklist").font(.title).foregroundStyle(.secondary)
                    Text("无待确认事项").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 32)
            }
            Spacer()
        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.windowBackgroundColor)
    }

    func completeApproval(_ item: ApprovalItem, approved: Bool) {
        pendingApprovals.removeAll { $0.id == item.id }
        completedItems.append(item)
    }
}

struct ApprovalItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let checkpoint: String
}
