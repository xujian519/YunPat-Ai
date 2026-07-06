import SwiftUI
import YunPatCore

/// 记忆卡片式 Dashboard
struct MemoryDashboardView: View {
    @State private var selectedLayer: MemoryLayer = .caseContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: Spacing.md) {
                    StatCard(
                        title: "工作记忆",
                        value: "12",
                        icon: "bolt",
                        trend: "当前会话",
                        color: .blue
                    )
                    StatCard(
                        title: "会话事实",
                        value: "48",
                        icon: "bubble.left",
                        trend: "最近 24h",
                        color: .purple
                    )
                    StatCard(
                        title: "案件上下文",
                        value: "6",
                        icon: "folder",
                        trend: "持久化",
                        color: .orange
                    )
                    StatCard(
                        title: "长期记忆",
                        value: "128",
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("记忆")
                .font(FontStyle.largeTitle)
            Text("五层记忆架构的统一视图")
                .font(FontStyle.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var layerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("记忆层级")
                .font(FontStyle.title2)

            Picker("层级", selection: $selectedLayer) {
                ForEach(MemoryLayer.allCases, id: \.self) { layer in
                    Text(layerLabel(layer)).tag(layer)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("最近条目")
                .font(FontStyle.title2)

            VStack(spacing: Spacing.xs) {
                MemoryEntryRow(content: "用户偏好：答复使用简体中文", source: "手动编辑", time: "10 分钟前")
                MemoryEntryRow(content: "本案 IPC: G06F17/30", source: "会话提取", time: "1 小时前")
                MemoryEntryRow(content: "检索策略：优先 Google Patents CN", source: "策略学习", time: "3 小时前")
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
