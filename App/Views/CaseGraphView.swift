import SwiftUI
import YunPatCore

/// 案件关系图 — 在协作面板中以 🗂 切换
struct CaseGraphView: View {
    let caseId: String?
    @State private var relations: [CaseRelation] = []

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "point.topleft.down.curvedto.point.filled")
                    .foregroundStyle(.blue)
                Text("案件关系")
                    .font(.headline)
                Spacer()
                if !relations.isEmpty {
                    Button {
                        Task { await loadRelations() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal)

            if let caseId = caseId {
                // 当前案件节点
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text("本案")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(caseId)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        Spacer()
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(6)

                    if !relations.isEmpty {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 1, height: 16)
                    }

                    ForEach(relations) { relation in
                        HStack(spacing: 6) {
                            Image(systemName: relationIcon(relation.relationType))
                                .font(.caption)
                                .foregroundStyle(relationColor(relation.relationType))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(relation.relationType.rawValue)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text(relation.toCaseTitle)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                if let appNo = relation.applicationNumber {
                                    Text(appNo)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                        }
                        .padding(6)
                        .background(relationColor(relation.relationType).opacity(0.05))
                        .cornerRadius(4)
                    }

                    if relations.isEmpty {
                        Text("暂无关联案件记录")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                }
                .onAppear { Task { await loadRelations() } }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("当前标签未绑定案件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("在案件标签中使用 🗂 查看关系")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackgroundColor)
    }

    private func loadRelations() async {
        guard let caseId else { return }
        relations = await CaseRelationStore.shared.relations(for: caseId)
    }

    private func relationIcon(_ type: CaseRelationType) -> String {
        switch type {
        case .priority: return "arrow.up.doc"
        case .divisional: return "arrow.down.doc"
        case .reference: return "doc.text"
        case .family: return "rectangle.stack"
        case .continuation: return "arrow.triangle.branch"
        }
    }

    private func relationColor(_ type: CaseRelationType) -> Color {
        switch type {
        case .priority: return .orange
        case .divisional: return .purple
        case .reference: return .gray
        case .family: return .green
        case .continuation: return .teal
        }
    }
}
