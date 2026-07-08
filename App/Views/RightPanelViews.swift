import SwiftUI
import YunPatCore

/// 右栏文件资源管理器包装视图
struct RightFileExplorerView: View {
    @StateObject var workspaceManager: CaseWorkspaceManager
    @ObservedObject var tabManager: TabManager
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    var body: some View {
        VStack(spacing: 0) {
            RightPanelHeader(title: "资源管理器", icon: "folder") {
                appState.toggleRightPanel(.fileExplorer)
            }
            Divider()
            FileBrowserView(workspaceManager: workspaceManager, tabManager: tabManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appSidebarBackground)
    }
}

/// 右栏文档视图
struct RightDocumentView: View {
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    var body: some View {
        VStack(spacing: 0) {
            RightPanelHeader(title: documentTitle, icon: "doc.text") {
                appState.toggleRightPanel(.document)
            }
            Divider()
            DocumentWorkspace(selectedFileURL: $appState.selectedDocumentURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appSidebarBackground)
    }

    private var documentTitle: String {
        appState.selectedDocumentURL?.lastPathComponent ?? "文档"
    }
}

// MARK: - Right Panel Placeholders

struct RightSkillGalleryView: View {
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    var body: some View {
        VStack(spacing: 0) {
            RightPanelHeader(title: "技能库", icon: "sparkles") {
                appState.toggleRightPanel(.skills)
            }
            Divider()
            SkillGalleryView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appSidebarBackground)
    }
}

struct RightRoutingDashboardView: View {
    let caseId: String?
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    var body: some View {
        VStack(spacing: 0) {
            RightPanelHeader(title: "路由", icon: "arrow.triangle.branch") {
                appState.toggleRightPanel(.routing)
            }
            Divider()
            RoutingDashboardView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appSidebarBackground)
    }
}

struct RightMemoryDashboardView: View {
    let caseId: String?
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    var body: some View {
        VStack(spacing: 0) {
            RightPanelHeader(title: "记忆", icon: "brain") {
                appState.toggleRightPanel(.memory)
            }
            Divider()
            MemoryDashboardView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appSidebarBackground)
    }
}

struct RightAlwaysOnDashboardView: View {
    @ObservedObject private var appState: AppStateStore = AppStateStore.shared

    var body: some View {
        VStack(spacing: 0) {
            RightPanelHeader(title: "常驻", icon: "pin") {
                appState.toggleRightPanel(.alwaysOn)
            }
            Divider()
            AlwaysOnDashboardView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appSidebarBackground)
    }
}

// MARK: - Header

struct RightPanelHeader: View {
    let title: String
    let icon: String
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: IconSize.inlineSmall))
                .foregroundStyle(Color.appTextSecondary)
            Text(title)
                .font(FontStyle.callout)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appTextPrimary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: IconSize.caption, weight: .medium))
                    .foregroundStyle(Color.appTextSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.appSurfacePrimary)
    }
}
