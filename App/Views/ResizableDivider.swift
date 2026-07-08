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
                    }
            )
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.set()
                } else if !isDragging {
                    NSCursor.arrow.set()
                }
            }
            .animation(.easeInOut(duration: AnimationDuration.fast), value: isHovered)
            .animation(.easeInOut(duration: AnimationDuration.fast), value: isDragging)
            .accessibilityLabel("调整面板宽度")
            .accessibilityHint("左右拖动调整相邻面板宽度")
    }

    private var fillColor: Color {
        if isDragging {
            return Color.accentColor
        }
        return isHovered ? Color.appSeparator.opacity(0.8) : Color.appSeparator.opacity(0.4)
    }
}
