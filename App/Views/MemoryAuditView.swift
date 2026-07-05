import SwiftUI
import YunPatCore

struct MemoryAuditView: View {
    @StateObject private var manager: MemoryAuditManager = MemoryAuditManager()
    @State private var editingContent: String = ""
    @State private var selectedLayer: MemoryLayerFilter = .all
    @State private var selectedSource: MemorySourceFilter = .all

    enum MemoryLayerFilter: String, CaseIterable {
        case all = "全部层级"
        case caseContext = "案件"
        case longTerm = "长期"
        case global = "全局"
    }

    enum MemorySourceFilter: String, CaseIterable {
        case all = "全部来源"
        case sessionFact = "会话事实"
        case manualEdit = "手动编辑"
        case consolidation = "合并"
    }

    var body: some View {
        HSplitView {
            entryList
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)

            detailPanel
                .frame(minWidth: 320)
        }
        .task { await manager.load() }
    }

    // MARK: - List

    private var entryList: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()

            if manager.entries.isEmpty {
                EmptyStateView(
                    icon: "brain.head.profile",
                    title: "暂无记忆",
                    subtitle: "当前案件或筛选条件下没有可审计的记忆条目",
                    action: nil
                )
                .padding(.top, Spacing.xl)
            } else {
                List(filteredEntries, selection: Binding(
                    get: { manager.selectedEntry?.id },
                    set: { newID in
                        if let entry = manager.entries.first(where: { $0.id == newID }) {
                            manager.select(entry)
                            editingContent = entry.content
                        }
                    }
                )) { entry in
                    EntryRow(entry: entry)
                        .tag(entry.id)
                        .listRowBackground(
                            entry.id == manager.selectedEntry?.id
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear
                        )
                }
                .listStyle(.plain)
            }
        }
        .background(.thickMaterial)
    }

    private var filterBar: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("记忆审计")
                    .font(FontStyle.headline)
                Spacer()
                if manager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal)
            .padding(.top, Spacing.sm)

            HStack(spacing: Spacing.sm) {
                Picker("层级", selection: $selectedLayer) {
                    ForEach(MemoryLayerFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("来源", selection: $selectedSource) {
                    ForEach(MemorySourceFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)
            .padding(.bottom, Spacing.sm)
        }
    }

    private var filteredEntries: [AuditableMemoryEntry] {
        manager.entries.filter { entry in
            let layerMatch: Bool = switch selectedLayer {
            case .all: true
            case .caseContext: entry.layer == .caseContext
            case .longTerm: entry.layer == .longTerm
            case .global: entry.layer == .global
            }
            let sourceMatch: Bool = switch selectedSource {
            case .all: true
            case .sessionFact: entry.source == .sessionFact
            case .manualEdit: entry.source == .manualEdit
            case .consolidation: entry.source == .consolidation
            }
            return layerMatch && sourceMatch && !entry.isArchived
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPanel: some View {
        if let entry = manager.selectedEntry {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header(for: entry)
                Divider()

                TextEditor(text: $editingContent)
                    .font(FontStyle.bodyMonospaced)
                    .frame(minHeight: 120)

                metadata(for: entry)
                Spacer()
                actionButtons(for: entry)
            }
            .padding()
            .background(.background)
        } else {
            EmptyStateView(
                icon: "doc.text.magnifyingglass",
                title: "选择记忆条目",
                subtitle: "在左侧列表中选择一个条目以查看详情、编辑或审计",
                action: nil
            )
        }
    }

    private func header(for entry: AuditableMemoryEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.content.isEmpty ? "（空内容）" : entry.content)
                    .font(FontStyle.headline)
                    .lineLimit(2)

                HStack(spacing: Spacing.xs) {
                    LayerBadge(layer: entry.layer)
                    SourceBadge(source: entry.source)
                    if entry.isPinned {
                        Label("已固定", systemImage: "pin.fill")
                            .font(FontStyle.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
        }
    }

    private func metadata(for entry: AuditableMemoryEntry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            MetadataRow(label: "ID", value: entry.id.uuidString)
            if let caseId = entry.caseId {
                MetadataRow(label: "案件", value: caseId)
            }
            if let turn = entry.sourceTurn {
                MetadataRow(label: "对话轮次", value: "\(turn)")
            }
            if let tool = entry.toolCall, !tool.isEmpty {
                MetadataRow(label: "工具调用", value: tool)
            }
            MetadataRow(label: "置信度", value: String(format: "%.2f", entry.confidence))
            MetadataRow(label: "创建时间", value: entry.createdAt.formatted())
            MetadataRow(label: "修改时间", value: entry.modifiedAt.formatted())
        }
        .font(FontStyle.caption)
        .foregroundStyle(.secondary)
    }

    private func actionButtons(for entry: AuditableMemoryEntry) -> some View {
        HStack(spacing: Spacing.sm) {
            Button("保存修改") {
                Task { await manager.update(content: editingContent) }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(editingContent == entry.content)

            Button {
                Task { await manager.togglePin(entry) }
            } label: {
                Label(entry.isPinned ? "取消固定" : "固定", systemImage: entry.isPinned ? "pin.slash" : "pin")
            }

            Button {
                Task { await manager.rollback(entry) }
            } label: {
                Label("回滚", systemImage: "arrow.uturn.backward")
            }
            .disabled(entry.source == .manualEdit)

            Spacer()

            Button(role: .destructive) {
                Task { await manager.delete(entry) }
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(entry.isPinned)
        }
        .controlSize(.regular)
    }
}

// MARK: - Subviews

private struct EntryRow: View {
    let entry: AuditableMemoryEntry

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: entry.isPinned ? "pin.fill" : "circle.fill")
                .foregroundStyle(colorForLayer(entry.layer))
                .font(.system(size: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.content)
                    .font(FontStyle.callout)
                    .lineLimit(2)
                HStack(spacing: Spacing.xs) {
                    Text(entry.source.rawValue)
                        .font(FontStyle.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(entry.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(FontStyle.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if entry.isArchived {
                Text("已归档")
                    .font(FontStyle.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
    }
}

private struct LayerBadge: View {
    let layer: MemoryLayer

    var body: some View {
        Text(layer.rawValue)
            .font(FontStyle.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colorForLayer(layer).opacity(0.15))
            .foregroundStyle(colorForLayer(layer))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs))
    }
}

private struct SourceBadge: View {
    let source: MemorySource

    var body: some View {
        Text(source.rawValue)
            .font(FontStyle.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.15))
            .foregroundStyle(.secondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs))
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

private func colorForLayer(_ layer: MemoryLayer) -> Color {
    switch layer {
    case .working: return .purple
    case .session: return .blue
    case .caseContext: return .green
    case .longTerm: return .orange
    case .global: return .pink
    }
}

#Preview {
    MemoryAuditView()
        .frame(width: 800, height: 500)
}
