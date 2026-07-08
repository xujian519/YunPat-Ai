import SwiftUI
import YunPatCore

struct CostDashboardView: View {
    @StateObject private var manager: CostDashboardManager = CostDashboardManager()
    let caseId: String?

    init(caseId: String? = nil) {
        self.caseId = caseId
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if manager.isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                Spacer()
            } else if let snap = manager.snapshot {
                ScrollView(.vertical) {
                    VStack(spacing: Spacing.md) {
                        budgetGauges(snap)
                        recentUsage
                    }
                    .padding()
                }
            } else {
                EmptyStateView(
                    icon: "chart.pie",
                    title: "暂无预算数据",
                    subtitle: "开始对话后自动生成使用统计",
                    action: nil
                )
                .padding(.top, Spacing.xl)
            }
        }
        .task { await manager.load(caseId: caseId) }
        .onChange(of: caseId) { _, newId in
            Task { await manager.load(caseId: newId) }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Image(systemName: "chart.pie")
                .foregroundStyle(.secondary)
            Text("成本仪表盘")
                .font(FontStyle.headline)
            Spacer()
            if manager.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            if manager.snapshot != nil {
                Button {
                    Task { await manager.resetGlobal() }
                } label: {
                    Label("重置全局", systemImage: "arrow.counterclockwise")
                        .font(FontStyle.caption)
                }
                .buttonStyle(.plain)
                .help("重置全局月度预算计数")
            }
        }
        .padding(.horizontal)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xs)
    }

    // MARK: - Gauges

    private func budgetGauges(_ snap: TokenBudgetSnapshot) -> some View {
        VStack(spacing: Spacing.md) {
            GaugeRowView(
                title: "Token 使用",
                used: Double(snap.usedTokens),
                total: Double(snap.caseBudgetTokens),
                percent: snap.percentTokens,
                color: snap.isOverBudget ? .red : .accentColor
            )
            GaugeRowView(
                title: "美元花费",
                used: snap.usedUsd,
                total: snap.caseBudgetUsd,
                percent: snap.percentUsd,
                color: snap.isOverBudget ? .red : .orange
            )
            Text(snap.isOverBudget
                 ? "⚠️ 预算已用尽，后续调用将使用降级模型或受限策略"
                 : "剩余 Token: \(snap.remainingTokens) | 剩余金额: $\(String(format: "%.4f", snap.remainingUsd))")
                .font(FontStyle.caption)
                .foregroundStyle(snap.isOverBudget ? .red : .secondary)
        }
    }
}

// MARK: - GaugeRowView

private struct GaugeRowView: View {
    let title: String
    let used: Double
    let total: Double
    let percent: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack {
                Text(title)
                    .font(FontStyle.callout)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(formatted(used)) / \(formatted(total))")
                    .font(FontStyle.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: percent, total: 100)
                .tint(color)
                .accessibleAnimation(.easeInOut, value: percent)
        }
    }

    private func formatted(_ value: Double) -> String {
        if title == "Token 使用" {
            return "\(Int(value))"
        }
        return String(format: "$%.4f", value)
    }
}

// MARK: - Recent Usage (inside CostDashboardView)

extension CostDashboardView {
    var recentUsage: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("最近调用")
                .font(FontStyle.headline)
                .padding(.bottom, Spacing.xxs)

            if manager.recentRecords.isEmpty {
                Text("暂无记录")
                    .font(FontStyle.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(manager.recentRecords) { record in
                    UsageRow(record: record)
                }
            }
        }
    }
}

// MARK: - UsageRow

private struct UsageRow: View {
    let record: TokenUsageRecord

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(record.provider) / \(record.model)")
                    .font(FontStyle.caption)
                    .foregroundStyle(.primary)
                HStack(spacing: Spacing.xxs) {
                    Text("⬆ \(record.inputTokens)")
                        .foregroundStyle(.secondary)
                    Text("⬇ \(record.outputTokens)")
                        .foregroundStyle(.secondary)
                    Text("$\(String(format: "%.4f", record.costUsd))")
                        .foregroundStyle(.orange)
                }
                .font(FontStyle.caption2)
            }
            Spacer()
            Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(FontStyle.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    CostDashboardView()
        .frame(width: 320, height: 500)
}
