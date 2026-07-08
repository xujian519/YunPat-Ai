import SwiftUI

/// PilotDeck 风格统计卡片
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let trend: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: IconSize.inlineSmall, weight: .medium))
                    .foregroundStyle(color)
                Text(title)
                    .font(FontStyle.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }

            Text(value)
                .font(FontStyle.title)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appTextPrimary)

            Text(trend)
                .font(FontStyle.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .appCard()
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
