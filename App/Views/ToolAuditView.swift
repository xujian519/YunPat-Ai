import SwiftUI
import YunPatCore

struct ToolAuditView: View {
    @StateObject private var manager: ToolAuditManager = ToolAuditManager()

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            summaryBar
            searchBar
            Divider()
            entryList
        }
        .frame(minWidth: PanelWidth.toolAuditMin, idealWidth: PanelWidth.toolAuditIdeal)
        .task { await manager.load() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Image(systemName: "list.bullet.clipboard")
                .foregroundStyle(.secondary)
            Text("工具审计").font(.headline)
            Spacer()
            Button("导出 JSON") {
                Task {
                    guard let data: Data = await manager.exportJSON() else { return }
                    let panel: NSSavePanel = NSSavePanel()
                    panel.nameFieldStringValue = "tool_audit_export.json"
                    panel.begin { response in
                        if response == .OK, let url = panel.url {
                            try? data.write(to: url)
                        }
                    }
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Button("清空") {
                Task { await manager.clear() }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .font(.caption)
        }
        .padding(.horizontal).padding(.vertical, 6)
    }

    // MARK: - Summary

    private var summaryBar: some View {
        HStack(spacing: 12) {
            if let summary: ToolAuditRecorder.AuditSummary = manager.summary {
                Label("\(summary.totalCalls) 次调用", systemImage: "number")
                    .font(.caption).foregroundStyle(.secondary)
                Label("\(summary.totalErrors) 次错误", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(summary.totalErrors > 0 ? .red : .secondary)
                if let top: String = summary.mostCalled {
                    Label("最常用: \(top)", systemImage: "chart.bar")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if manager.isLoading {
                Spacer()
                ProgressView().scaleEffect(0.6)
            }
        }
        .padding(.horizontal).padding(.vertical, 4)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索工具名或结果...", text: $manager.searchText)
                .textFieldStyle(.plain)
                .font(.caption)
                .onChange(of: manager.searchText) { _, _ in
                    Task { await manager.search() }
                }
            if !manager.searchText.isEmpty {
                Button { manager.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal).padding(.vertical, 4)
    }

    // MARK: - Entry List

    private var entryList: some View {
        List(selection: $manager.selectedEntry) {
            ForEach(manager.filteredEntries) { entry in
                ToolAuditRow(entry: entry)
                    .tag(entry)
                    .onTapGesture { manager.select(entry) }
            }
        }
        .listStyle(.plain)
        .alternatingRowBackgrounds()
    }
}

// MARK: - ToolAuditRow

private struct ToolAuditRow: View {
    let entry: ToolAuditRecorder.AuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: entry.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(entry.isError ? .red : .green)
                    .font(.caption)
                Text(entry.toolName)
                    .font(.subheadline).fontWeight(.medium)
                Spacer()
                Text(durationString)
                    .font(.caption2).foregroundStyle(.secondary)
                Text(entry.timestamp, style: .time)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(entry.inputSummary)
                .font(.caption).foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(entry.resultSummary)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
            if entry.permissionDecision != "allow" {
                Label(entry.permissionDecision, systemImage: "lock.shield")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var durationString: String {
        if entry.duration < 1 { return "\(Int(entry.duration * 1000))ms" }
        if entry.duration < 60 { return String(format: "%.1fs", entry.duration) }
        return String(format: "%.0fm", entry.duration / 60)
    }
}
