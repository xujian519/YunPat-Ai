import SwiftUI
import YunPatCore

/// 技能库中心视图：浏览与编辑 SKILL.md
struct SkillGalleryView: View {
    @StateObject private var manager = SkillGalleryManager()
    @State private var selectedSkill: SkillPreview?
    @State private var isEditing: Bool = false

    var body: some View {
        HSplitView {
            skillList
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            skillDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await manager.load()
            if selectedSkill == nil {
                selectedSkill = skillPreviews.first
            }
        }
    }

    private var skillPreviews: [SkillPreview] {
        manager.skills.map { SkillPreview(from: $0) }
    }

    private var skillList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(Color.accentColor)
                Text("技能")
                    .font(FontStyle.headline)
                Spacer()
                if manager.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding()

            List(selection: $selectedSkill) {
                ForEach(skillPreviews) { skill in
                    SkillRow(skill: skill)
                        .tag(skill)
                }
            }
            .listStyle(.sidebar)
        }
        .background(.thickMaterial)
    }

    @ViewBuilder
    private var skillDetail: some View {
        if let skill = selectedSkill {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    title: skill.displayName,
                    subtitle: skill.path,
                    actions: {
                        HStack(spacing: Spacing.xs) {
                            Button(
                                action: { Task { await manager.refresh() } },
                                label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: IconSize.toolbar))
                                }
                            )
                            .buttonStyle(.plain)

                            Button(
                                action: {},
                                label: {
                                    HStack(spacing: Spacing.xxs) {
                                        Image(systemName: "plus")
                                            .font(.system(size: IconSize.inlineSmall, weight: .bold))
                                        Text("新建")
                                            .font(FontStyle.callout)
                                    }
                                }
                            )
                            .buttonStyle(.plain)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.appTextPrimary)
                            .foregroundStyle(Color.appSurfacePrimary)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                        }
                    }
                )
                .padding()

                Divider()

                if !skill.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.xxs) {
                            ForEach(skill.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(FontStyle.caption2)
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                    .padding(.vertical, Spacing.xs)
                }

                HStack {
                    Spacer()
                    Toggle("编辑", isOn: $isEditing)
                        .toggleStyle(.switch)
                        .padding(.trailing, Spacing.md)
                }
                .padding(.vertical, Spacing.xs)

                ScrollView {
                    Text(skill.markdown)
                        .font(FontStyle.body)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color.appBackground)
        } else {
            EmptyStateView(
                icon: "wand.and.stars",
                title: "选择技能",
                subtitle: manager.skills.isEmpty ? "尚未加载任何技能" : "从左侧选择要查看的 SKILL.md",
                action: nil
            )
        }
    }
}

struct SkillPreview: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let displayName: String
    let path: String
    let markdown: String
    let tags: [String]
    let triggers: [String]

    init(from match: SkillMatch) {
        let manifest: SkillManifest = match.manifest
        self.name = manifest.name
        self.displayName = manifest.displayName.isEmpty ? manifest.name : manifest.displayName
        self.path = "~/.agents/skills/\(manifest.name)/SKILL.md"
        self.markdown = match.skill.body
        self.tags = manifest.tags
        self.triggers = manifest.triggers
    }
}

struct SkillRow: View {
    let skill: SkillPreview

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "doc.text")
                .font(.system(size: IconSize.caption))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.displayName)
                    .font(FontStyle.callout)
                Text(skill.path)
                    .font(FontStyle.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SkillGalleryView()
        .frame(width: 900, height: 600)
}
