import SwiftUI

/// 三段式状态栏，类比 Zed StatusBar
///
/// ```
/// Left（面板切换）    | Center（操作）    | Right（Dock 切换 + 状态）
/// [📁案][📁树][📚知]  | [📎][💾][↻]       | [🌐][🤝][📄]  💻 已连接
/// ```
struct StatusBar: View {
    @Binding var filePickerOpen: Bool
    var onSave: () -> Void
    var onSync: () -> Void

    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    var body: some View {
        HStack(spacing: 0) {
            leftSection

            Divider()
                .frame(height: Spacing.md)
                .padding(.horizontal, Spacing.xs)

            centerSection

            Spacer()

            rightSection

            connectionIndicator
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .frame(height: PanelWidth.statusBarHeight)
        .background(.thickMaterial)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.appSeparator.opacity(0.5)),
            alignment: .top
        )
    }

    // MARK: - Left Section: Left Dock panel switching

    private var leftSection: some View {
        HStack(spacing: Spacing.xxs) {
            StatusBarButton(
                icon: "folder",
                help: "案件列表",
                isActive: appState.leftDockActivePanel == .caseList && appState.leftDockVisible,
                action: { appState.leftDockActivePanel = .caseList; appState.leftDockVisible = true }
            )
            StatusBarButton(
                icon: "briefcase",
                help: "案件工作区",
                isActive: appState.leftDockActivePanel == .caseWorkspace && appState.leftDockVisible,
                action: { appState.leftDockActivePanel = .caseWorkspace; appState.leftDockVisible = true }
            )
            StatusBarButton(
                icon: "books.vertical",
                help: "知识库",
                isActive: appState.leftDockActivePanel == .knowledge && appState.leftDockVisible,
                action: { appState.leftDockActivePanel = .knowledge; appState.leftDockVisible = true }
            )
        }
        .padding(.leading, Spacing.xxs)
    }

    // MARK: - Center Section: Tool actions

    private var centerSection: some View {
        HStack(spacing: Spacing.xxs) {
            StatusBarButton(icon: "paperclip", help: "打开文件", action: { filePickerOpen = true })
            StatusBarButton(icon: "square.and.arrow.down", help: "保存", action: onSave)
            StatusBarButton(icon: "arrow.triangle.2.circlepath", help: "同步至 Agent", action: onSync)
        }
    }

    // MARK: - Right Section: Dock toggles + center mode

    private var rightSection: some View {
        HStack(spacing: Spacing.xxs) {
            StatusBarButton(
                icon: "safari",
                help: "专利浏览器",
                isActive: appState.centerMode == .browser,
                action: { appState.centerMode = appState.centerMode == .browser ? .chat : .browser }
            )
            StatusBarButton(
                icon: "checklist",
                help: "协作面板",
                isActive: appState.rightDockVisible,
                action: { appState.rightDockVisible.toggle() }
            )
            StatusBarButton(
                icon: "doc.text",
                help: "文档工作区",
                isActive: appState.bottomDockVisible,
                action: { appState.bottomDockVisible.toggle() }
            )
        }
    }

    // MARK: - Connection indicator

    private var connectionIndicator: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(Color.statusSuccess)
            Text("已连接")
                .font(FontStyle.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, Spacing.sm)
        .accessibilityLabel("连接状态: 已连接")
    }
}

// MARK: - StatusBarButton

struct StatusBarButton: View {
    let icon: String
    let help: String
    var isActive: Bool = false
    var action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: IconSize.toolbar, weight: .medium))
                .foregroundStyle(foregroundStyle)
                .frame(width: HitTarget.small, height: HitTarget.small)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(backgroundStyle)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
                isHovered = hovering
            }
        }
    }

    private var foregroundStyle: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(Color.accentColor)
        } else if isHovered {
            return AnyShapeStyle(Color.primary)
        }
        return AnyShapeStyle(Color.appTextSecondary)
    }

    private var backgroundStyle: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        } else if isHovered {
            return AnyShapeStyle(Color.appSurfaceTertiary)
        }
        return AnyShapeStyle(Color.clear)
    }
}
