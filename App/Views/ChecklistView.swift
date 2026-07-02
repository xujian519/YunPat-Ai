import SwiftUI

/// 实时 checklist 视图 — 解析 todo 工具的 markdown 清单
struct ChecklistView: View {
    let markdown: String
    @State private var checkedItems: Set<Int> = []

    var body: some View {
        let items = parseChecklist(markdown)
        if items.isEmpty {
            return AnyView(EmptyView())
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Label("任务清单", systemImage: "checklist")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Button(action: { toggleItem(index) }, label: {
                            Image(systemName: checkedItems.contains(index) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(checkedItems.contains(index) ? Color.green : Color.secondary)
                                .font(.system(size: 14))
                        })
                        .buttonStyle(.plain)

                        Text(item)
                            .font(.system(size: 13))
                            .strikethrough(checkedItems.contains(index))
                            .foregroundStyle(checkedItems.contains(index) ? Color.secondary : Color.primary)
                    }
                }
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.1), lineWidth: 1)
            )
            .padding(.vertical, 4)
        )
    }

    private func parseChecklist(_ markdownInput: String) -> [String] {
        let lines = markdownInput.components(separatedBy: .newlines)
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let range = trimmed.range(of: #"-\s\[[\sxX]\]\s"#, options: .regularExpression) {
                return String(trimmed[range.upperBound...])
            }
            return nil
        }
    }

    private func toggleItem(_ index: Int) {
        if checkedItems.contains(index) {
            checkedItems.remove(index)
        } else {
            checkedItems.insert(index)
        }
    }
}
