import SwiftUI

/// 统一的空状态视图，用于列表、面板、工作区无数据场景。
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String?
    let action: EmptyAction?

    init(icon: String, title: String, subtitle: String? = nil, action: EmptyAction? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    struct EmptyAction {
        let title: String
        let icon: String
        let handler: () -> Void

        init(title: String, icon: String = "plus", handler: @escaping () -> Void) {
            self.title = title
            self.icon = icon
            self.handler = handler
        }
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: IconSize.emptyState, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 72)
                .background(
                    Circle()
                        .fill(Color.appSurfaceSecondary)
                )

            Text(title)
                .font(FontStyle.callout)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(FontStyle.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, Spacing.md)
            }

            if let action {
                Button {
                    action.handler()
                } label: {
                    Label(action.title, systemImage: action.icon)
                        .font(FontStyle.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#if DEBUG
#Preview("EmptyState") {
    EmptyStateView(
        icon: "folder",
        title: "暂无案件",
        subtitle: "创建新案件开始专利代理工作",
        action: .init(title: "新建案件", icon: "plus") {}
    )
    .frame(width: 260, height: 300)
}
#endif
