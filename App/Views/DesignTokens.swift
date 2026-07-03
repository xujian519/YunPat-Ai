import SwiftUI

enum Spacing {
    static let unit: CGFloat = 4
    static let xxs: CGFloat = unit * 1
    static let xs: CGFloat = unit * 2
    static let sm: CGFloat = unit * 3
    static let md: CGFloat = unit * 4
    static let lg: CGFloat = unit * 5
    static let xl: CGFloat = unit * 6
}

enum CornerRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12
}

enum FontStyle {
    static let largeTitle: Font = .system(size: 26, weight: .bold)
    static let title2: Font = .system(size: 19, weight: .semibold)
    static let headline: Font = .system(size: 13, weight: .bold)
    static let body: Font = .system(size: 13)
    static let bodyMonospaced: Font = .system(size: 13, design: .monospaced)
    static let callout: Font = .system(size: 12)
    static let caption: Font = .system(size: 10)
    static let caption2: Font = .system(size: 9)
    static let tiny: Font = .system(size: 8)
}

enum PanelWidth {
    static let sidebarMin: CGFloat = 200
    static let sidebarIdeal: CGFloat = 240
    static let sidebarMax: CGFloat = 300
    static let collaborationMin: CGFloat = 240
    static let collaborationIdeal: CGFloat = 280
    static let collaborationMax: CGFloat = 360
    static let folderTreeMin: CGFloat = 200
    static let folderTreeIdeal: CGFloat = 260
    static let flowPicker: CGFloat = 280
}

enum AnimationDuration {
    static let fast: CGFloat = 0.1
    static let normal: CGFloat = 0.2
    static let slow: CGFloat = 0.25
    static let spring: CGFloat = 0.3
}

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
