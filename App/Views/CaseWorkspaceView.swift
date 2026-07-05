import SwiftUI
import YunPatCore

/// 案件工作区左侧面板：整合工作区元数据与文件树。
struct CaseWorkspaceView: View {
    @StateObject private var manager: CaseWorkspaceManager
    @State private var notesDraft: String = ""
    @State private var tagsDraft: String = ""
    @State private var pathDraft: String = ""

    private let tabManager: TabManager

    init(manager: CaseWorkspaceManager, tabManager: TabManager) {
        _manager = StateObject(wrappedValue: manager)
        self.tabManager = tabManager
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let workspace = manager.selectedWorkspace {
                workspaceBody(workspace: workspace)
            } else {
                emptyState
            }
        }
        .background(.thickMaterial)
        .onChange(of: manager.selectedWorkspace?.id) { _, _ in
            notesDraft = manager.selectedWorkspace?.notes ?? ""
            tagsDraft = manager.selectedWorkspace?.tags.joined(separator: ", ") ?? ""
            pathDraft = manager.selectedWorkspace?.workspacePath ?? ""
            syncTabPath(manager.selectedWorkspace?.workspacePath)
        }
        .task {
            notesDraft = manager.selectedWorkspace?.notes ?? ""
            tagsDraft = manager.selectedWorkspace?.tags.joined(separator: ", ") ?? ""
            pathDraft = manager.selectedWorkspace?.workspacePath ?? ""
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "briefcase")
                .foregroundStyle(Color.accentColor)
            Text("案件工作区")
                .font(FontStyle.headline)
            Spacer()
            if manager.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "briefcase",
            title: "无工作区",
            subtitle: manager.selectedCaseId == nil
                ? "请先选择一个案件标签"
                : "当前案件尚未创建工作区",
            action: manager.selectedCaseId == nil
                ? nil
                : .init(title: "创建工作区", icon: "plus") {
                    Task {
                        await manager.ensureWorkspace(
                            title: activeTabTitle ?? "新案件",
                            caseId: manager.selectedCaseId ?? ""
                        )
                    }
                }
        )
        .padding(.top, Spacing.xl)
    }

    // MARK: - Workspace Body

    private func workspaceBody(workspace: CaseWorkspace) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    metadataCard(workspace: workspace)
                    statusSection(workspace: workspace)
                    tagsSection(workspace: workspace)
                    notesSection(workspace: workspace)
                    Divider()
                    folderTreeSection(workspace: workspace)
                }
                .padding()
            }
        }
    }

    private func metadataCard(workspace: CaseWorkspace) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(workspace.title)
                .font(FontStyle.headline)
            if !workspace.caseId.isEmpty {
                Text(workspace.caseId)
                    .font(FontStyle.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("修改: \(workspace.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(FontStyle.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }

    private func statusSection(workspace: CaseWorkspace) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("状态")
                .font(FontStyle.caption)
                .foregroundStyle(.secondary)
            Picker("状态", selection: Binding(
                get: { workspace.status },
                set: { newStatus in
                    Task { await manager.updateStatus(newStatus) }
                }
            )) {
                ForEach(CaseWorkspaceStatus.allCases, id: \.self) { status in
                    Text(status.rawValue).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func tagsSection(workspace: CaseWorkspace) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("标签")
                .font(FontStyle.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.xs) {
                TextField("用逗号分隔标签", text: $tagsDraft)
                    .textFieldStyle(.plain)
                    .font(FontStyle.callout)
                Button {
                    Task { await saveTags() }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(tagsDraft == workspace.tags.joined(separator: ", "))
            }
            .padding(Spacing.xs)
            .background(Color.appSurfaceSecondary)
            .cornerRadius(CornerRadius.md)
        }
    }

    private func notesSection(workspace: CaseWorkspace) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("备注")
                    .font(FontStyle.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await manager.updateNotes(notesDraft) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(notesDraft == workspace.notes)
            }
            TextEditor(text: $notesDraft)
                .font(FontStyle.body)
                .frame(minHeight: 80, idealHeight: 100)
                .padding(Spacing.xxs)
                .background(Color.appSurfaceSecondary)
                .cornerRadius(CornerRadius.md)
        }
    }

    private func folderTreeSection(workspace: CaseWorkspace) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("工作目录")
                    .font(FontStyle.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await manager.updatePath(pathDraft.isEmpty ? nil : pathDraft) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(pathDraft == (workspace.workspacePath ?? ""))
            }

            TextField("路径", text: $pathDraft)
                .textFieldStyle(.plain)
                .font(FontStyle.caption)
                .padding(Spacing.xs)
                .background(Color.appSurfaceSecondary)
                .cornerRadius(CornerRadius.md)

            if let path = workspace.workspacePath, !path.isEmpty {
                FolderTreeView(rootPath: URL(fileURLWithPath: path))
                    .frame(minHeight: 160)
                    .background(Color.windowBackgroundColor)
                    .cornerRadius(CornerRadius.md)
            } else {
                EmptyStateView(
                    icon: "folder",
                    title: "未设置工作目录",
                    subtitle: "在上方输入路径以浏览文件",
                    action: nil
                )
                .frame(minHeight: 120)
            }
        }
    }

    // MARK: - Helpers

    private func saveTags() async {
        let trimmed = tagsDraft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        await manager.updateTags(trimmed)
    }

    private func syncTabPath(_ path: String?) {
        guard let caseId = manager.selectedCaseId,
              let index = tabManager.tabs.firstIndex(where: { $0.caseId == caseId })
        else { return }
        tabManager.tabs[index].workspacePath = path.map { URL(fileURLWithPath: $0) }
    }

    private var activeTabTitle: String? {
        tabManager.tabs.first { $0.caseId == manager.selectedCaseId }?.title
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    CaseWorkspaceView(manager: CaseWorkspaceManager(), tabManager: TabManager())
        .frame(width: 320, height: 600)
}
#endif
