import SwiftUI

// MARK: - Spacing (8pt 网格基准，HIG §Spacing)

enum Spacing {
    static let unit: CGFloat = 8
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = unit * 1
    static let sm: CGFloat = unit * 2
    static let md: CGFloat = unit * 3
    static let lg: CGFloat = unit * 4
    static let xl: CGFloat = unit * 5
    static let xxl: CGFloat = unit * 6
}

// MARK: - CornerRadius

enum CornerRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let full: CGFloat = 9999
}

// MARK: - Font (HIG 语义字体，支持 Dynamic Type)

enum FontStyle {
    static let largeTitle: Font = .largeTitle
    static let title: Font = .title
    static let title2: Font = .title2
    static let title3: Font = .title3
    static let headline: Font = .headline
    static let subheadline: Font = .subheadline
    static let body: Font = .body
    static let bodyMonospaced: Font = .body.monospaced()
    static let callout: Font = .callout
    static let caption: Font = .caption
    static let caption2: Font = .caption2
    static let footnote: Font = .footnote
}

// MARK: - Icon Size (SF Symbols 统一尺寸)

enum IconSize {
    static let toolbar: CGFloat = 16
    static let sidebar: CGFloat = 14
    static let inlineSmall: CGFloat = 12
    static let caption: CGFloat = 11
    static let emptyState: CGFloat = 40
    static let avatar: CGFloat = 28
    static let avatarInline: CGFloat = 13
    static let messageIcon: CGFloat = 24
    static let typingDot: CGFloat = 5
    static let hero: CGFloat = 56
}

// MARK: - Hit Target (HIG 最小触控区域 44pt)

enum HitTarget {
    static let minimum: CGFloat = 44
    static let small: CGFloat = 28
}

// MARK: - PanelWidth

enum PanelWidth {
    static let sidebarMin: CGFloat = 200
    static let sidebarIdeal: CGFloat = 240
    static let sidebarMax: CGFloat = 300
    static let collaborationMin: CGFloat = 240
    static let collaborationIdeal: CGFloat = 280
    static let collaborationMax: CGFloat = 360
    static let folderTreeMin: CGFloat = 200
    static let folderTreeIdeal: CGFloat = 260
    static let caseWorkspaceMin: CGFloat = 260
    static let caseWorkspaceIdeal: CGFloat = 300
    static let costDashboardMin: CGFloat = 260
    static let costDashboardIdeal: CGFloat = 300
    static let memoryAuditMin: CGFloat = 260
    static let memoryAuditIdeal: CGFloat = 320

    static let toolAuditMin: CGFloat = 280
    static let toolAuditIdeal: CGFloat = 360
    static let flowPicker: CGFloat = 240
    static let welcomeMax: CGFloat = 640
    static let suggestionCardMin: CGFloat = 200
    static let settingsWidth: CGFloat = 520
    static let settingsHeight: CGFloat = 480

    // Bottom Dock
    static let bottomDockMinHeight: CGFloat = 180
    static let bottomDockIdealHeight: CGFloat = 280

    // Right Panel
    static let rightPanelMin: CGFloat = 260
    static let rightPanelIdeal: CGFloat = 320
    static let rightPanelMax: CGFloat = 420
    static let statusBarHeight: CGFloat = 34
    static let topBarHeight: CGFloat = 48
}

// MARK: - Border

enum BorderWidth {
    static let hairline: CGFloat = 0.5
    static let thin: CGFloat = 1
}

// MARK: - Dock System

/// Dock 位置枚举。与 Zed 三 Dock 架构对齐。
public enum DockPosition: String, CaseIterable, Codable {
    case left
    case right
    case bottom
}

// MARK: - AnimationDuration

enum AnimationDuration {
    static let fast: CGFloat = 0.15
    static let normal: CGFloat = 0.2
    static let slow: CGFloat = 0.25
    static let spring: CGFloat = 0.35
    static let long: CGFloat = 0.45
}

// MARK: - Semantic Colors

extension Color {
    static let statusWarning: Color = .orange
    static let statusSuccess: Color = .green
    static let statusRunning: Color = .blue
    static let statusDestructive: Color = .red

    static let annotationDeletion: Color = .red
    static let annotationInsertion: Color = .green
    static let annotationQuestion: Color = .orange
    static let annotationComment: Color = .blue

    static let groupBackground: Color = .secondary
    static let interactiveOverlay: Color = .accentColor
}

// MARK: - Elevation / Shadow

enum AppShadow {
    static let sm = ShadowPair(
        light: ShadowStyle(color: Color.black.opacity(0.04), radius: 2, horizontal: 0, vertical: 1),
        dark: ShadowStyle(color: Color.black.opacity(0.45), radius: 6, horizontal: 0, vertical: 3)
    )
    static let md = ShadowPair(
        light: ShadowStyle(color: Color.black.opacity(0.06), radius: 6, horizontal: 0, vertical: 3),
        dark: ShadowStyle(color: Color.black.opacity(0.5), radius: 10, horizontal: 0, vertical: 5)
    )
    static let lg = ShadowPair(
        light: ShadowStyle(color: Color.black.opacity(0.08), radius: 12, horizontal: 0, vertical: 6),
        dark: ShadowStyle(color: Color.black.opacity(0.55), radius: 16, horizontal: 0, vertical: 8)
    )
    static let glow = ShadowPair(
        light: ShadowStyle(color: Color.accentColor.opacity(0.25), radius: 8, horizontal: 0, vertical: 0),
        dark: ShadowStyle(color: Color.accentColor.opacity(0.3), radius: 10, horizontal: 0, vertical: 0)
    )
}

/// 浅色 / 深色双套投影：深色下纯黑投影几乎不可见，改用更重的黑色 + 略大半径制造柔和暗晕。
struct ShadowPair {
    let light: ShadowStyle
    let dark: ShadowStyle

    func resolve(for scheme: ColorScheme) -> ShadowStyle {
        scheme == .dark ? dark : light
    }
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let horizontal: CGFloat
    let vertical: CGFloat

    func apply<V: View>(_ view: V) -> some View {
        view.shadow(color: color, radius: radius, x: horizontal, y: vertical)
    }
}
