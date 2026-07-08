import SwiftUI
import YunPatCore

/// PilotDeck 风格聊天输入栏
struct InputBar: View {
    @ObservedObject var chatManager: ChatManager
    @ObservedObject var tabManager: TabManager
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("告诉 YunPat-Ai 你想完成什么…", text: $chatManager.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(FontStyle.body)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .accessibilityLabel("消息输入框")
                .onSubmit {
                    if !sendDisabled {
                        Task { await chatManager.sendMessage(in: tabManager) }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)

            HStack(spacing: 0) {
                inputToolbar
                Spacer()
                sendButton
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(Color.appInputBarBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xl)
                        .stroke(isInputFocused ? Color.accentColor.opacity(0.5) : Color.appSeparator, lineWidth: 1)
                )
        )
        .padding(Spacing.md)
    }

    private var inputToolbar: some View {
        HStack(spacing: Spacing.sm) {
            ToolButton(icon: "sparkles", label: "智能体")
            ToolButton(icon: "paperclip", label: nil)
            ToolButton(icon: "at", label: nil)
            ToolButton(icon: "shield.fill", label: "完全访问权限", accent: true)
        }
    }

    private var sendButton: some View {
        Button {
            Task { await chatManager.sendMessage(in: tabManager) }
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: IconSize.toolbar, weight: .semibold))
                .foregroundStyle(sendDisabled ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.white))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(sendDisabled ? Color.appSurfaceTertiary : Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(sendDisabled)
        .keyboardShortcut(.return, modifiers: [.command])
        .accessibilityLabel("发送消息")
        .help("⌘ + Enter 发送")
    }

    private var sendDisabled: Bool {
        let trimmed: String = chatManager.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return chatManager.isStreaming || trimmed.isEmpty
    }
}

struct ToolButton: View {
    let icon: String
    var label: String?
    var accent: Bool = false

    @State private var isHovered: Bool = false

    var body: some View {
        Button(
            action: {},
            label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: icon)
                        .font(.system(size: IconSize.toolbar, weight: .medium))
                    if let label {
                        Text(label)
                            .font(FontStyle.callout)
                    }
                }
                .foregroundStyle(accent ? Color.orange : (isHovered ? Color.appTextPrimary : Color.appTextSecondary))
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(isHovered ? Color.appSurfaceTertiary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
            }
        )
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
                isHovered = hovering
            }
        }
    }
}
