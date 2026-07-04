import SwiftUI

// MARK: - Spacing (8pt 网格基准，HIG §Spacing)

enum Spacing {
    static let unit: CGFloat = 8
    static let xxs: CGFloat = 4
    static let xs: CGFloat = unit * 1
    static let sm: CGFloat = unit * 2
    static let md: CGFloat = unit * 3
    static let lg: CGFloat = unit * 4
    static let xl: CGFloat = unit * 5
}

// MARK: - CornerRadius

enum CornerRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12
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
}

// MARK: - Icon Size (SF Symbols 统一尺寸)

enum IconSize {
    static let toolbar: CGFloat = 16
    static let sidebar: CGFloat = 14
    static let inlineSmall: CGFloat = 12
    static let caption: CGFloat = 11
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
    static let flowPicker: CGFloat = 240
    static let settingsWidth: CGFloat = 520
    static let settingsHeight: CGFloat = 480

    // Bottom Dock
    static let bottomDockMinHeight: CGFloat = 180
    static let bottomDockIdealHeight: CGFloat = 280

    // StatusBar
    static let statusBarHeight: CGFloat = 32
}

// MARK: - Dock System

/// Dock 位置枚举。与 Zed 三 Dock 架构对齐。
public enum DockPosition: String, CaseIterable, Codable {
    case left
    case right
    case bottom
}

/// 中心区域内容模式。
public enum CenterMode: String, CaseIterable, Codable {
    case chat
    case browser
    case focusWriting
}

// MARK: - AnimationDuration

enum AnimationDuration {
    static let fast: CGFloat = 0.15
    static let normal: CGFloat = 0.2
    static let slow: CGFloat = 0.25
    static let spring: CGFloat = 0.35
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
