import SwiftUI
import YunPatCore

/// 顶部主导航栏：智能体 / 文件 / 技能 / 路由 / 记忆 / 常驻
struct TopModuleBar: View {
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: IconSize.toolbar))
                    .foregroundStyle(Color.accentColor)

                breadcrumb
            }

            Spacer()

            HStack(spacing: Spacing.xs) {
                ForEach(TopModule.allCases) { module in
                    moduleButton(module)
                }
            }

            Spacer()

            HStack(spacing: Spacing.xs) {
                Button {
                    NotificationCenter.default.post(name: .menuOpenFile, object: nil)
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: IconSize.toolbar))
                }
                .buttonStyle(.plain)
                .help("打开文件")

                Button {
                    NotificationCenter.default.post(name: .openSettingsTab, object: 0)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: IconSize.toolbar))
                }
                .buttonStyle(.plain)
                .help("设置")
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(height: PanelWidth.topBarHeight)
        .background(.thickMaterial)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.appSeparator.opacity(0.5)),
            alignment: .bottom
        )
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Text("YunPat-Ai")
                .font(FontStyle.callout)
                .foregroundStyle(.secondary)

            Text("/")
                .font(FontStyle.caption)
                .foregroundStyle(.tertiary)

            Text(appState.topModule.rawValue)
                .font(FontStyle.callout)
                .foregroundStyle(.primary)
        }
    }

    private func moduleButton(_ module: TopModule) -> some View {
        let isActive = appState.topModule == module
        return Button {
            withAnimation(.easeInOut(duration: AnimationDuration.fast)) {
                appState.topModule = module
                switch module {
                case .agent:
                    appState.centerMode = .chat
                case .files:
                    appState.centerMode = .files
                case .skills:
                    appState.centerMode = .skills
                case .routing:
                    appState.centerMode = .routing
                case .memory:
                    appState.centerMode = .memory
                case .alwaysOn:
                    appState.centerMode = .alwaysOn
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: module.icon)
                    .font(.system(size: IconSize.inlineSmall))
                Text(module.rawValue)
                    .font(FontStyle.callout)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
            .foregroundStyle(isActive ? Color.accentColor : Color.appTextSecondary)
            .cornerRadius(CornerRadius.md)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TopModuleBar()
        .frame(width: 900)
}
