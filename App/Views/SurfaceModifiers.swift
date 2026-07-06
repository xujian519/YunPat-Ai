import SwiftUI

// MARK: - 统一表面样式系统

/// 集中管理卡片（带高程投影）与嵌入式表面的视觉语言。
///
/// 让 `StatCard` / `ProviderStatusCard` / `PromptCard` / 设置卡片 等共享同一套
/// 背景、圆角、发丝描边与投影，消除“扁平卡片”观感，并真正启用 `DesignTokens`
/// 中已定义但此前未被引用的 `AppShadow` 高程系统。
extension View {
    /// 抬升卡片：表面背景 + 圆角 + 发丝描边 + 高程投影。
    /// - Parameters:
    ///   - elevation: 投影层级（默认 `.sm`）。
    ///   - cornerRadius: 圆角半径（默认 `CornerRadius.lg`）。
    func appCard(elevation: ShadowStyle = AppShadow.sm, cornerRadius: CGFloat = CornerRadius.lg) -> some View {
        elevation.apply(
            self
                .background(Color.appSurfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.appSeparator.opacity(0.5), lineWidth: BorderWidth.hairline)
                )
        )
    }

    /// 嵌入式表面：容器内的次级区块，仅描边、无外投影（如设置内的分组、策略区）。
    func appSurface(cornerRadius: CGFloat = CornerRadius.lg) -> some View {
        self
            .background(Color.appSurfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.appSeparator.opacity(0.5), lineWidth: BorderWidth.hairline)
            )
    }
}
