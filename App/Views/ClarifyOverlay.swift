import SwiftUI

/// Clarify 询问覆盖层 — 底部固定，等待用户选择一个答案或输入
struct ClarifyOverlay: View {
    let request: ClarifyRequestDisplay
    let onAnswer: (String) -> Void
    let onDismiss: () -> Void

    @State private var selectedOptions: Set<String> = []
    @State private var freeText: String = ""
    @FocusState private var isFreeTextFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(Color.statusWarning)
                Text("需要确认")
                    .font(FontStyle.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭确认面板")
            }

            Text(request.question)
                .font(FontStyle.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("问题：\(request.question)")

            if !request.options.isEmpty {
                if request.allowMultiple {
                    multiSelectOptions
                } else {
                    singleSelectOptions
                }
            }

            if request.options.isEmpty || request.allowMultiple {
                TextField("或输入你的回答...", text: $freeText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFreeTextFocused)
                    .accessibilityLabel("自由输入回答")
            }

            HStack {
                Spacer()
                Button("跳过") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("跳过当前确认")

                Button("确认") {
                    let answer = buildAnswer()
                    guard !answer.isEmpty else { return }
                    onAnswer(answer)
                }
                .buttonStyle(.borderedProminent)
                .disabled(buildAnswer().isEmpty)
                .accessibilityLabel("提交确认")
            }
        }
        .padding()
        .background(Color(named: "windowBackground"))
        .cornerRadius(CornerRadius.xl)
        .shadow(radius: 8)
        .padding()
        .onAppear {
            if request.options.isEmpty {
                isFreeTextFocused = true
            }
        }
    }

    private var singleSelectOptions: some View {
        VStack(spacing: Spacing.xxs) {
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
                    .padding(Spacing.xs)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(CornerRadius.md)
                })
                .buttonStyle(.plain)
                .accessibilityLabel("选择：\(option)")
            }
        }
    }

    private var multiSelectOptions: some View {
        VStack(spacing: Spacing.xxs) {
            ForEach(request.options.prefix(6), id: \.self) { option in
                Button(action: { toggleOption(option) }, label: {
                    HStack {
                        Image(systemName: selectedOptions.contains(option) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selectedOptions.contains(option) ? Color.accentColor : Color.secondary)
                        Text(option)
                        Spacer()
                    }
                    .padding(Spacing.xs)
                    .background(Color.accentColor.opacity(0.05))
                    .cornerRadius(CornerRadius.md)
                })
                .buttonStyle(.plain)
                .accessibilityLabel("\(selectedOptions.contains(option) ? "已选中" : "未选中")：\(option)")
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
