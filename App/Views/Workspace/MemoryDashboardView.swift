import SwiftUI
import YunPatCore

/// PilotDeck 风格记忆 Dashboard
struct MemoryDashboardView: View {
    @StateObject private var manager = MemoryDashboardManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                PageHeader(
                    title: "记忆",
                    subtitle: "五层记忆架构的统一视图",
                    actions: {
                        Button(
                            action: { Task { await manager.load() } },
                            label: {
                                HStack(spacing: Spacing.xxs) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: IconSize.inlineSmall))
                                    Text("刷新")
                                        .font(FontStyle.callout)
                                }
                            }
                        )
                        .buttonStyle(.plain)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs)
                        .background(Color.appSurfacePrimary)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .stroke(Color.appSeparator.opacity(0.5), lineWidth: BorderWidth.hairline)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                    }
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: Spacing.md) {
                    StatCard(
                        title: "工作记忆",
                        value: "\(manager.layerCounts[.working] ?? 0)",
                        icon: "bolt",
                        trend: "当前会话",
                        color: .blue
                    )
                    StatCard(
                        title: "会话事实",
                        value: "\(manager.layerCounts[.session] ?? 0)",
                        icon: "bubble.left",
                        trend: "最近 24h",
                        color: .purple
                    )
                    StatCard(
                        title: "案件上下文",
                        value: "\(manager.layerCounts[.caseContext] ?? 0)",
                        icon: "folder",
                        trend: "持久化",
                        color: .orange
                    )
                    StatCard(
                        title: "长期记忆",
                        value: "\(manager.layerCounts[.longTerm] ?? 0)",
                        icon: "brain.head.profile",
                        trend: "已巩固",
                        color: .green
                    )
                }

                layerSection
                recentEntriesSection
            }
            .padding(Spacing.lg)
        }
        .background(Color.appBackground)
        .task { await manager.load() }
    }

    private var layerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("记忆层级")

            Picker("层级", selection: Binding(
                get: { manager.selectedLayer },
                set: { manager.selectLayer($0) }
            )) {
                ForEach(MemoryLayer.allCases, id: \.self) { layer in
                    Text(layerLabel(layer)).tag(layer)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("最近条目")

            if manager.filteredEntries.isEmpty {
                EmptyStateView(
                    icon: "brain",
                    title: "暂无记忆",
                    subtitle: "该层级还没有持久化的记忆条目",
                    action: nil
                )
                .padding(.vertical, Spacing.lg)
                .appCard()
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(Array(manager.filteredEntries.prefix(10)), id: \.id) { entry in
                        MemoryEntryRow(
                            content: entry.description.isEmpty ? entry.name : entry.description,
                            source: "[\(entry.type.rawValue)] \(entry.name)",
                            time: entry.id
                        )
                    }
                }
            }
        }
    }

    private func layerLabel(_ layer: MemoryLayer) -> String {
        switch layer {
        case .working: return "工作"
        case .session: return "会话"
        case .caseContext: return "案件"
        case .longTerm: return "长期"
        case .global: return "全局"
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(FontStyle.callout)
            .fontWeight(.semibold)
            .foregroundStyle(Color.appTextSecondary)
    }
}

struct MemoryEntryRow: View {
    let content: String
    let source: String
    let time: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(content)
                    .font(FontStyle.callout)
                HStack(spacing: Spacing.xs) {
                    Text(source)
                        .font(FontStyle.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(time)
                        .font(FontStyle.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .appCard(cornerRadius: CornerRadius.md)
    }
}

#Preview {
    MemoryDashboardView()
        .frame(width: 900, height: 600)
}
