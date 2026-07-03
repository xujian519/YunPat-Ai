import SwiftUI
import YunPatCore

/// 案件关系图 — 在协作面板中以 🗂 切换
struct CaseGraphView: View {
    let caseId: String?
    @State private var relations: [CaseRelation] = []

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "point.topleft.down.curvedto.point.filled")
                    .foregroundStyle(.blue)
                Text("案件关系")
                    .font(FontStyle.headline)
                Spacer()
                if !relations.isEmpty {
                    Button {
                        Task { await loadRelations() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("刷新关系图")
                }
            }
            .padding(.horizontal)

            if let caseId = caseId {
                VStack(spacing: Spacing.xs) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text("本案")
                                .font(FontStyle.caption)
                                .foregroundStyle(.secondary)
                            Text(caseId)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        Spacer()
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    }
                    .padding(Spacing.xs)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(CornerRadius.md)

                    if !relations.isEmpty {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 1, height: Spacing.md)
                    }

                    ForEach(relations) { relation in
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: relationIcon(relation.relationType))
                                .font(.caption)
                                .foregroundStyle(relationColor(relation.relationType))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(relation.relationType.rawValue)
                                    .font(FontStyle.caption2)
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
                        .padding(Spacing.xxs)
                        .background(relationColor(relation.relationType).opacity(0.05))
                        .cornerRadius(CornerRadius.sm)
                    }

                    if relations.isEmpty {
                        Text("暂无关联案件记录")
                            .font(FontStyle.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, Spacing.xxs)
                    }
                }
                .onAppear { Task { await loadRelations() } }
            } else {
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("当前标签未绑定案件")
                        .font(FontStyle.caption)
                        .foregroundStyle(.secondary)
                    Text("在案件标签中使用 🗂 查看关系")
                        .font(FontStyle.tiny)
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
