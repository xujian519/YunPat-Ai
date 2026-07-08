import SwiftUI
import YunPatCore

/// PilotDeck 风格聊天欢迎页
struct ChatWelcomeView: View {
    let onPromptTap: (String) -> Void

    private let suggestions: [PromptSuggestion] = [
        PromptSuggestion(icon: "doc.text.magnifyingglass", title: "检索对比文件", prompt: "帮我检索与本案相关的对比文件"),
        PromptSuggestion(icon: "pencil", title: "起草权利要求", prompt: "根据技术交底书起草权利要求"),
        PromptSuggestion(icon: "bubble.left", title: "答复审查意见", prompt: "分析这份审查意见并给出答复思路"),
        PromptSuggestion(icon: "globe", title: "专利翻译", prompt: "将这段专利摘要翻译成英文")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("今天想做点什么？")
                .font(FontStyle.title)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appTextPrimary)

            Spacer()

            // 保留快捷入口，但以更克制的方式呈现
            HStack(spacing: Spacing.md) {
                ForEach(suggestions) { suggestion in
                    SuggestionPill(suggestion: suggestion) {
                        onPromptTap(suggestion.prompt)
                    }
                }
            }
            .padding(.bottom, Spacing.xl)
        }
        .padding(.horizontal, Spacing.xl)
    }
}

struct PromptSuggestion: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let prompt: String
}

struct SuggestionPill: View {
    let suggestion: PromptSuggestion
    let action: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: IconSize.inlineSmall))
                    .foregroundStyle(Color.appTextSecondary)
                Text(suggestion.title)
                    .font(FontStyle.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule()
                    .fill(isHovering ? Color.appSurfaceSecondary : Color.appSurfacePrimary)
            )
            .overlay(
                Capsule()
                    .stroke(Color.appSeparator.opacity(0.5), lineWidth: BorderWidth.hairline)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    ChatWelcomeView { _ in }
        .frame(width: 900, height: 600)
}
