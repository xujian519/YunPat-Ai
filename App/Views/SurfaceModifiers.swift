import SwiftUI

// MARK: - 统一表面样式系统

/// 集中管理卡片（带高程投影）与嵌入式表面的视觉语言。
///
/// 让 `StatCard` / `ProviderStatusCard` / `PromptCard` / 设置卡片 等共享同一套
/// 背景、圆角、发丝描边与投影，消除“扁平卡片”观感，并真正启用 `DesignTokens`
/// 中已定义但此前未被引用的 `AppShadow` 高程系统。
extension View {
    /// 抬升卡片：表面背景 + 圆角 + 发丝描边 + 高程投影（浅/深色自适应）。
    /// - Parameters:
    ///   - elevation: 投影层级（默认 `.sm`）。
    ///   - cornerRadius: 圆角半径（默认 `CornerRadius.lg`）。
    ///   - surface: 表面底色（默认 `appSurfacePrimary`）。
    func appCard(
        elevation: ShadowPair = AppShadow.sm,
        cornerRadius: CGFloat = CornerRadius.lg,
        surface: Color = .appSurfacePrimary
    ) -> some View {
        self.modifier(_AppCard(elevation: elevation, cornerRadius: cornerRadius, surface: surface))
    }

    /// 嵌入式表面：容器内的次级区块，仅描边、无外投影（如设置内的分组、策略区、输入框）。
    /// - Parameters:
    ///   - cornerRadius: 圆角半径。
    ///   - surface: 表面底色（默认 `appSurfacePrimary`，次级面板可用 `appSurfaceSecondary`）。
    func appSurface(
        cornerRadius: CGFloat = CornerRadius.lg,
        surface: Color = .appSurfacePrimary
    ) -> some View {
        self
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.appSeparator.opacity(0.5), lineWidth: BorderWidth.hairline)
            )
    }
}

/// 内部修饰器：读取 `colorScheme` 以在浅/深色下分别选用 `ShadowPair` 的投影，
/// 并随主题调整发丝描边强度（深色下更明显以维持边界分离）。
private struct _AppCard: ViewModifier {
    let elevation: ShadowPair
    let cornerRadius: CGFloat
    let surface: Color
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    func body(content: Content) -> some View {
        let shadow = elevation.resolve(for: colorScheme)
        content
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.appSeparator.opacity(colorScheme == .dark ? 0.9 : 0.5),
                            lineWidth: BorderWidth.hairline)
            )
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.horizontal, y: shadow.vertical)
    }
}
