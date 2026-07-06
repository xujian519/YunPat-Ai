import SwiftUI
import YunPatCore

/// 文件浏览器中心视图
struct FileBrowserView: View {
    @StateObject var workspaceManager: CaseWorkspaceManager
    @ObservedObject var tabManager: TabManager

    var body: some View {
        HSplitView {
            if let workspace = workspaceManager.selectedWorkspace,
               let path = workspace.workspacePath, !path.isEmpty {
                FolderTreeView(rootPath: URL(fileURLWithPath: path))
                    .frame(minWidth: PanelWidth.folderTreeMin, idealWidth: PanelWidth.folderTreeIdeal)
            } else {
                EmptyStateView(
                    icon: "folder",
                    title: "未设置工作目录",
                    subtitle: workspaceManager.selectedCaseId == nil
                        ? "请先在项目列表选择一个项目"
                        : "当前项目尚未配置工作目录",
                    action: workspaceManager.selectedCaseId == nil
                        ? nil
                        : .init(title: "创建工作区", icon: "plus") {
                            Task {
                                await workspaceManager.ensureWorkspace(
                                    title: activeTabTitle ?? "新项目",
                                    caseId: workspaceManager.selectedCaseId ?? ""
                                )
                            }
                        }
                )
                .frame(minWidth: PanelWidth.folderTreeMin, idealWidth: PanelWidth.folderTreeIdeal)
                .background(.thickMaterial)
            }

            DocumentWorkspace()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var activeTabTitle: String? {
        tabManager.tabs.first { $0.caseId == workspaceManager.selectedCaseId }?.title
    }
}

#Preview {
    FileBrowserView(workspaceManager: CaseWorkspaceManager(), tabManager: TabManager())
        .frame(width: 900, height: 600)
}
