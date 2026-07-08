import SwiftUI
import YunPatCore

/// PilotDeck 风格顶部模块导航按钮
struct TopModuleButton: View {
    let module: TopModule
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    var body: some View {
        Button(
            action: {
                AppHaptic.alignment()
                action()
            },
            label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: module.icon)
                        .font(.system(size: IconSize.toolbar, weight: .medium))
                    Text(module.rawValue)
                        .font(FontStyle.callout)
                }
                .foregroundStyle(foregroundStyle)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .frame(minHeight: HitTarget.small + Spacing.xxs)
                .background(backgroundStyle)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                .contentShape(RoundedRectangle(cornerRadius: CornerRadius.md))
            }
        )
        .buttonStyle(.plain)
        .help("\(module.rawValue) (⌘\(module.shortcutDigit))")
        .accessibilityLabel(module.rawValue)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .onHover { hovering in
            withAccessibleAnimation(reduceMotion: reduceMotion, duration: AnimationDuration.fast) {
                isHovered = hovering
            }
        }
    }

    private var foregroundStyle: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(Color.accentColor)
        } else if isHovered {
            return AnyShapeStyle(Color.appTextPrimary)
        }
        return AnyShapeStyle(Color.appTextSecondary)
    }

    private var backgroundStyle: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(Color.appSurfaceSecondary)
        } else if isHovered {
            return AnyShapeStyle(Color.appSurfaceTertiary)
        }
        return AnyShapeStyle(Color.clear)
    }
}
