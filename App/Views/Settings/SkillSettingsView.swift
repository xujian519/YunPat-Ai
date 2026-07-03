import SwiftUI
import YunPatCore

struct SkillSettingsView: View {
    @State private var skills: [SkillManifest] = []
    @State private var skillCount: Int = 0
    @State private var scanStatus: String = ""
    @State private var testInput: String = ""
    @State private var testResults: [SkillMatchDisplay] = []
    @State private var isLoading: Bool = false
    var body: some View {
        Form {
            // MARK: - 已加载技能
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("技能管理")
                            .font(.headline)
                        Spacer()
                        Text("已加载 \(skillCount) 个技能")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("技能 (Skill) 是轻量的 Prompt 注入片段，通过触发词、标签和语义匹配在对话中自动激活。与插件不同，技能不包含可执行代码。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // 操作按钮
                    HStack(spacing: 8) {
                        Button("从文件夹扫描…") { scanFolder() }
                            .disabled(isLoading)

                        Button("重新加载内置技能") { reloadBuiltin() }
                            .disabled(isLoading)

                        if !skills.isEmpty {
                            Button("清除全部", role: .destructive) { clearAll() }
                        }
                    }

                    if !scanStatus.isEmpty {
                        HStack(spacing: 4) {
                            Image(
                                systemName: scanStatus.contains("成功")
                                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(scanStatus.contains("成功") ? .green : .orange)
                            .font(.system(size: 12))
                            Text(scanStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            } header: {
                Label("技能库", systemImage: "wand.and.stars")
            }

            // MARK: - 技能列表
            if !skills.isEmpty {
                Section("已加载技能 (\(skills.count))") {
                    ForEach(skills, id: \.name) { skill in
                        skillRow(skill)
                    }
                }
            } else if !isLoading {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("暂无技能")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("从文件夹扫描 .skill.md 文件，或点击「重新加载内置技能」")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }

            // MARK: - 匹配测试
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("匹配测试")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack {
                        TextField("输入测试文本…", text: $testInput)
                            .textFieldStyle(.roundedBorder)
                        Button("测试") { testMatch() }
                            .disabled(testInput.isEmpty || skills.isEmpty)
                    }

                    if !testResults.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(testResults, id: \.name) { result in
                                HStack {
                                    Circle()
                                        .fill(scoreColor(result.score))
                                        .frame(width: 8, height: 8)
                                    Text(result.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(String(format: "%.1f", result.score))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !result.reason.isEmpty {
                                    Text(result.reason)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            } header: {
                Label("匹配测试", systemImage: "magnifyingglass")
            }
        }
        .padding()
        .frame(minWidth: 450, minHeight: 400)
        .task { await refreshSkills() }
    }

    // MARK: - Skill Row

    private func skillRow(_ skill: SkillManifest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(skill.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("v\(skill.version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 4) {
                if !skill.tags.isEmpty {
                    ForEach(skill.tags.prefix(5), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                if !skill.triggers.isEmpty {
                    Text("触发词: \(skill.triggers.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            if !skill.author.isEmpty {
                Text("作者: \(skill.author)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func refreshSkills() async {
        let mgr: SkillManager = .shared
        let all: [SkillMatch] = await mgr.allSkills()
        await MainActor.run {
            skills = all.map { $0.skill.manifest }
            skillCount = all.count
        }
    }

    private func scanFolder() {
        let panel: NSOpenPanel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "选择包含 .skill.md 文件的目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isLoading = true
        scanStatus = ""
        Task {
            do {
                let mgr: SkillManager = .shared
                let loaded: [SkillManifest] = try await mgr.scan(from: url)
                await MainActor.run {
                    scanStatus = loaded.isEmpty ? "未找到 .skill.md 文件" : "成功加载 \(loaded.count) 个技能"
                    isLoading = false
                }
                await refreshSkills()
            } catch {
                await MainActor.run {
                    scanStatus = "加载失败: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func reloadBuiltin() {
        isLoading = true
        scanStatus = ""
        Task {
            do {
                let mgr: SkillManager = .shared
                let loaded: [SkillManifest] = try await mgr.loadBuiltinSkills()
                await MainActor.run {
                    scanStatus = loaded.isEmpty ? "未找到内置技能 (App/Resources/Skills/ 为空)" : "成功加载 \(loaded.count) 个内置技能"
                    isLoading = false
                }
                await refreshSkills()
            } catch {
                await MainActor.run {
                    scanStatus = "加载失败: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func clearAll() {
        Task {
            await SkillManager.shared.removeAll()

            await refreshSkills()
            await MainActor.run { testResults = [] }
        }
    }

    func testMatch() {
        guard !testInput.isEmpty else { return }
        Task {
            let mgr: SkillManager = .shared
            let request: UserRequest = UserRequest(content: testInput)
            let matches: [SkillMatch] = await mgr.match(for: request)
            await MainActor.run {
                testResults = matches.map { match in
                    SkillMatchDisplay(
                        name: match.skill.manifest.displayName,
                        score: match.score,
                        reason: matchReason(match)
                    )
                }
            }
        }
    }

    private func matchReason(_ match: SkillMatch) -> String {
        var reasons: [String] = []
        if match.score >= 10 { reasons.append("触发词命中") }
        if match.score.truncatingRemainder(dividingBy: 10) >= 2 { reasons.append("标签匹配") }
        let frac = match.score - Double(Int(match.score))
        if frac > 0 { reasons.append("语义相似") }
        return reasons.joined(separator: " + ")
    }

    private func scoreColor(_ score: Double) -> Color {
        score >= 10 ? .green : score >= 5 ? .blue : score >= 2 ? .orange : .gray
    }
}

/// 简化的结果显示
private struct SkillMatchDisplay {
    let name: String
    let score: Double
    let reason: String
}
