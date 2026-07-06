import SwiftUI

/// 通用统计卡片组件
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let trend: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: IconSize.messageIcon))
                    .foregroundStyle(color)
                Spacer()
                Text(trend)
                    .font(FontStyle.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(FontStyle.title)
                .fontWeight(.semibold)
            Text(title)
                .font(FontStyle.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(Color.appSurfacePrimary)
        .cornerRadius(CornerRadius.lg)
    }
}

#Preview {
    StatCard(
        title: "今日 Token",
        value: "42K",
        icon: "text.alignleft",
        trend: "+8%",
        color: .blue
    )
    .frame(width: 220)
}
