import SwiftUI

/// 案件关系图 — 在协作面板中以 🗂 切换
struct CaseGraphView: View {
    let caseId: String?
    let relatedCases: [RelatedCase]

    struct RelatedCase: Identifiable, Sendable {
        let id: String
        let title: String
        let relation: RelationType
    }

    enum RelationType: String, Sendable {
        case priority = "优先权"
        case divisional = "分案"
        case reference = "对比文件"
        case family = "同族"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "point.topleft.down.curvedto.point.filled")
                    .foregroundStyle(.blue)
                Text("案件关系")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            if let caseId = caseId {
                // 当前案件节点
                VStack(spacing: 8) {
                    // 中心节点
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

                    // 连接线
                    if !relatedCases.isEmpty {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 1, height: 16)
                    }

                    // 关联案件
                    ForEach(relatedCases) { rc in
                        HStack(spacing: 6) {
                            Image(systemName: relationIcon(rc.relation))
                                .font(.caption)
                                .foregroundStyle(relationColor(rc.relation))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rc.relation.rawValue)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text(rc.title)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(6)
                        .background(relationColor(rc.relation).opacity(0.05))
                        .cornerRadius(4)
                    }
                }
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

    private func relationIcon(_ type: RelationType) -> String {
        switch type {
        case .priority: return "arrow.up.doc"
        case .divisional: return "arrow.down.doc"
        case .reference: return "doc.text"
        case .family: return "rectangle.stack"
        }
    }

    private func relationColor(_ type: RelationType) -> Color {
        switch type {
        case .priority: return .orange
        case .divisional: return .purple
        case .reference: return .gray
        case .family: return .green
        }
    }
}
