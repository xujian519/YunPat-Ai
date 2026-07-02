import SwiftUI

/// Clarify 询问覆盖层 — 底部固定，等待用户选择一个答案或输入
struct ClarifyOverlay: View {
    let request: ClarifyRequestDisplay
    let onAnswer: (String) -> Void
    let onDismiss: () -> Void

    @State private var selectedOptions: Set<String> = []
    @State private var freeText: String = ""

    var body: some View {
        VStack(spacing: 12) {
            // 提示栏
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
                Text("需要确认")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // 问题
            Text(request.question)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 选项
            if !request.options.isEmpty {
                if request.allowMultiple {
                    multiSelectOptions
                } else {
                    singleSelectOptions
                }
            }

            // 自由输入
            if request.options.isEmpty || request.allowMultiple {
                TextField("或输入你的回答...", text: $freeText)
                    .textFieldStyle(.roundedBorder)
            }

            // 确认按钮
            HStack {
                Spacer()
                Button("跳过") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("确认") {
                    let answer = buildAnswer()
                    guard !answer.isEmpty else { return }
                    onAnswer(answer)
                }
                .buttonStyle(.borderedProminent)
                .disabled(buildAnswer().isEmpty)
            }
        }
        .padding()
        .background(Color(named: "windowBackground"))
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding()
    }

    private var singleSelectOptions: some View {
        VStack(spacing: 6) {
            ForEach(request.options.prefix(6), id: \.self) { option in
                Button(action: { onAnswer(option) }, label: {
                    HStack {
                        Text(option)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
                })
                .buttonStyle(.plain)
            }
        }
    }

    private var multiSelectOptions: some View {
        VStack(spacing: 6) {
            ForEach(request.options.prefix(6), id: \.self) { option in
                Button(action: { toggleOption(option) }, label: {
                    HStack {
                        Image(systemName: selectedOptions.contains(option) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selectedOptions.contains(option) ? Color.accentColor : Color.secondary)
                        Text(option)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.05))
                    .cornerRadius(6)
                })
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleOption(_ option: String) {
        if selectedOptions.contains(option) {
            selectedOptions.remove(option)
        } else {
            selectedOptions.insert(option)
        }
    }

    private func buildAnswer() -> String {
        if !freeText.trimmingCharacters(in: .whitespaces).isEmpty {
            return freeText.trimmingCharacters(in: .whitespaces)
        }
        if request.allowMultiple {
            return selectedOptions.sorted().joined(separator: ", ")
        }
        return ""
    }
}

extension Color {
    init(named: String) {
        self.init(NSColor(named: named) ?? NSColor.windowBackgroundColor)
    }
}
