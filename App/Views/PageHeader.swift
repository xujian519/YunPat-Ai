import SwiftUI

/// PilotDeck 风格页面头部：左侧标题/副标题 + 右侧操作区
struct PageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let actions: Actions

    init(
        title: String,
        subtitle: String,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(FontStyle.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)
                Text(subtitle)
                    .font(FontStyle.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
            }

            Spacer()

            actions
        }
    }
}

#Preview {
    PageHeader(
        title: "路由",
        subtitle: "模型路由策略与实时成本监控",
        actions: {
            Button("刷新") {}
        }
    )
    .padding()
}
