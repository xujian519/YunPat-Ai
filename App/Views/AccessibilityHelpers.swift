import AppKit
import SwiftUI

// MARK: - Reduce-Motion 动画辅助 (HIG §Accessibility — Motion)

/// 条件动画修饰器：当 `accessibilityReduceMotion` 为 true 时跳过动画。
struct ConditionalAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        if reduceMotion || animation == nil {
            content
        } else {
            content.animation(animation, value: value)
        }
    }
}

extension View {
    /// HIG 合规的动画修饰器 — 自动尊重用户的"减少动态效果"偏好。
    func accessibleAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(ConditionalAnimation(animation: animation, value: value))
    }
}

/// `withAnimation` 的无障碍封装：reduceMotion 时直接执行，不附带动画。
@MainActor
func withAccessibleAnimation(
    reduceMotion: Bool,
    duration: CGFloat = AnimationDuration.normal,
    body: () -> Void
) {
    if reduceMotion {
        body()
    } else {
        withAnimation(.easeInOut(duration: duration), body)
    }
}

// MARK: - Haptic Feedback (HIG §Feedback — Haptics)

enum AppHaptic {
    /// 轻量级对齐反馈 — 用于标签切换、面板展开等
    static func alignment() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// 通用准备反馈 — 用于发送消息、操作完成等
    static func generic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// 等级变化反馈 — 用于分段选择器切换
    static func levelChange() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

// MARK: - 命中区域扩展 (HIG §Hit Targets — 44pt minimum)

extension View {
    /// 将视觉上较小的控件扩展到 HIG 要求的 44pt 最小命中区域。
    /// 内容居中放置，contentShape 覆盖整个 44pt 区域。
    func minimumHitTarget() -> some View {
        self
            .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
            .contentShape(Rectangle())
    }
}
