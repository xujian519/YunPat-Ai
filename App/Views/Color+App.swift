import SwiftUI

extension Color {
    static let windowBackgroundColor = Color(nsColor: .windowBackgroundColor)

    // MARK: - Surface

    static let appBackground = Color(nsColor: .textBackgroundColor)
    static let appSurfacePrimary = Color(nsColor: .controlBackgroundColor)
    static let appSurfaceSecondary = Color(nsColor: .secondarySystemFill)
    static let appSurfaceTertiary = Color(nsColor: .tertiarySystemFill)
    static let appSurfaceQuaternary = Color(nsColor: .quaternarySystemFill)

    /// PilotDeck 风格侧边栏背景：比主背景略暖的浅灰
    static let appSidebarBackground = Color(nsColor: .windowBackgroundColor)

    // MARK: - Text

    static let appTextPrimary = Color(nsColor: .labelColor)
    static let appTextSecondary = Color(nsColor: .secondaryLabelColor)
    static let appTextTertiary = Color(nsColor: .tertiaryLabelColor)
    static let appTextPlaceholder = Color(nsColor: .placeholderTextColor)

    // MARK: - Separator

    static let appSeparator = Color(nsColor: .separatorColor)
    static let appGridLine = Color(nsColor: .gridColor)

    // MARK: - Control

    static let appControlBackground = Color(nsColor: .controlColor)
    static let appControlHighlight = Color(nsColor: .selectedControlColor)
    static let appControlText = Color(nsColor: .controlTextColor)
    static let appSelectedText = Color(nsColor: .selectedTextColor)

    // MARK: - Semantic surfaces

    static let appBubbleUser: Color = Color.accentColor.opacity(0.12)
    static let appBubbleAssistant: Color = Color(nsColor: .controlBackgroundColor)
    static let appBubbleUserText: Color = Color.accentColor
    static let appInputBarBackground: Color = Color(nsColor: .textBackgroundColor)

    // MARK: - Status badges

    static let appStatusSuccessSoft: Color = Color.green.opacity(0.12)
    static let appStatusWarningSoft: Color = Color.orange.opacity(0.12)
    static let appStatusRunningSoft: Color = Color.blue.opacity(0.12)

    /// 中性软背景：用于无语义强调的徽章/标签（如流程标签）。
    static let appStatusNeutralSoft: Color = Color.secondary.opacity(0.12)
    /// 破坏性操作软背景。
    static let appStatusDestructiveSoft: Color = Color.red.opacity(0.12)
    /// 强调色软背景：用于强调色按钮/指示器（如模型选择器）。
    static let appAccentSoft: Color = Color.accentColor.opacity(0.1)
}
