import SwiftUI
import YunPatCore

/// 聊天欢迎页：展示建议提示与快捷入口
struct ChatWelcomeView: View {
    let onPromptTap: (String) -> Void

    private let suggestions: [PromptSuggestion] = [
        PromptSuggestion(icon: "doc.text.magnifyingglass", title: "检索对比文件", prompt: "帮我检索与本案相关的对比文件"),
        PromptSuggestion(icon: "pencil", title: "起草权利要求", prompt: "根据技术交底书起草权利要求"),
        PromptSuggestion(icon: "bubble.left", title: "答复审查意见", prompt: "分析这份审查意见并给出答复思路"),
        PromptSuggestion(icon: "globe", title: "专利翻译", prompt: "将这段专利摘要翻译成英文")
    ]

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: IconSize.hero, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.8))
                .padding(.bottom, Spacing.sm)

            Text("YunPat-Ai")
                .font(FontStyle.largeTitle)
                .fontWeight(.semibold)

            Text("今天想处理什么专利代理工作？")
                .font(FontStyle.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: PanelWidth.suggestionCardMin))], spacing: Spacing.md) {
                ForEach(suggestions) { suggestion in
                    PromptCard(suggestion: suggestion) {
                        onPromptTap(suggestion.prompt)
                    }
                }
            }
            .padding(.top, Spacing.lg)
            .frame(maxWidth: PanelWidth.welcomeMax)

            Spacer()
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

struct PromptCard: View {
    let suggestion: PromptSuggestion
    let action: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: IconSize.messageIcon))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text(suggestion.title)
                        .font(FontStyle.callout)
                        .foregroundStyle(.primary)
                    Text(suggestion.prompt)
                        .font(FontStyle.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: IconSize.inlineSmall))
                    .foregroundStyle(.tertiary)
            }
            .padding(Spacing.sm)
            .background(isHovering ? Color.appSurfaceSecondary : Color.appSurfacePrimary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
                isHovering = hovering
            }
        }
        .appCard()
    }
}

#Preview {
    ChatWelcomeView { _ in }
        .frame(width: 900, height: 600)
}
