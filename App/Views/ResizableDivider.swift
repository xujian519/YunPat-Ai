import SwiftUI

/// 可拖拽调整相邻面板宽度的竖向分隔条。
///
/// 悬停时高亮并切换为左右缩放光标；拖拽时通过 `onWidthChange(delta)`
/// 把水平位移传给父视图更新面板宽度。
struct ResizableDivider: View {
    var minWidth: CGFloat = 200
    var maxWidth: CGFloat = 420
    @Binding var currentWidth: CGFloat
    var onWidthChange: ((CGFloat) -> Void)?

    @State private var isHovered: Bool = false
    @State private var isDragging: Bool = false
    @State private var dragStartWidth: CGFloat = 0
    @State private var cursorPushed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    var body: some View {
        Rectangle()
            .fill(fillColor)
            .frame(width: isHovered || isDragging ? 4 : 1)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartWidth = currentWidth
                        }
                        let newWidth: CGFloat = dragStartWidth + value.translation.width
                        let clamped: CGFloat = min(max(newWidth, minWidth), maxWidth)
                        let delta: CGFloat = clamped - currentWidth
                        guard delta != 0 else { return }
                        onWidthChange?(delta)
                    }
                    .onEnded { _ in
                        isDragging = false
                        resetCursor()
                    }
            )
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    pushCursor()
                } else if !isDragging {
                    resetCursor()
                }
            }
            .onDisappear {
                resetCursor()
            }
            .accessibleAnimation(.easeInOut(duration: AnimationDuration.fast), value: isHovered)
            .accessibleAnimation(.easeInOut(duration: AnimationDuration.fast), value: isDragging)
            .accessibilityLabel("调整面板宽度")
            .accessibilityHint("左右拖动调整相邻面板宽度")
            .accessibilityAdjustableAction { direction in
                let delta: CGFloat
                switch direction {
                case .increment: delta = 20
                case .decrement: delta = -20
                @unknown default: delta = 0
                }
                let newWidth = min(max(currentWidth + delta, minWidth), maxWidth)
                onWidthChange?(newWidth - currentWidth)
            }
    }

    private var fillColor: Color {
        if isDragging {
            return Color.accentColor
        }
        return isHovered ? Color.appSeparator.opacity(0.8) : Color.appSeparator.opacity(0.4)
    }

    // MARK: - Cursor Management

    private func pushCursor() {
        guard !cursorPushed else { return }
        NSCursor.resizeLeftRight.push()
        cursorPushed = true
    }

    private func resetCursor() {
        guard cursorPushed else { return }
        NSCursor.pop()
        cursorPushed = false
    }
}
