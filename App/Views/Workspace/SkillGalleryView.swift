import SwiftUI
import YunPatCore

/// 技能库中心视图：浏览与编辑 SKILL.md
struct SkillGalleryView: View {
    @State private var selectedSkill: SkillPreview? = sampleSkills.first
    @State private var isEditing: Bool = false

    var body: some View {
        HSplitView {
            skillList
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            skillDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var skillList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(Color.accentColor)
                Text("技能")
                    .font(FontStyle.headline)
                Spacer()
            }
            .padding()

            List(selection: $selectedSkill) {
                ForEach(sampleSkills) { skill in
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
                    title: skill.name,
                    subtitle: skill.path,
                    actions: {
                        HStack(spacing: Spacing.xs) {
                            Button(
                                action: {},
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

                HStack {
                    Spacer()
                    Toggle("编辑", isOn: $isEditing)
                        .toggleStyle(.switch)
                        .padding(.trailing, Spacing.md)
                }
                .padding(.vertical, Spacing.xs)

                ScrollView {
                    if isEditing {
                        TextEditor(text: .constant(skill.markdown))
                            .font(FontStyle.bodyMonospaced)
                            .padding()
                    } else {
                        Text(skill.markdown)
                            .font(FontStyle.body)
                            .padding()
                    }
                }
            }
            .background(Color.appBackground)
        } else {
            EmptyStateView(
                icon: "wand.and.stars",
                title: "选择技能",
                subtitle: "从左侧选择要查看或编辑的 SKILL.md",
                action: nil
            )
        }
    }
}

struct SkillPreview: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let markdown: String
}

struct SkillRow: View {
    let skill: SkillPreview

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "doc.text")
                .font(.system(size: IconSize.caption))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
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

private let sampleSkills: [SkillPreview] = [
    SkillPreview(
        name: "专利检索",
        path: "~/.agents/skills/google-patents-search/SKILL.md",
        markdown: "# Google Patents 检索\n\n用于检索专利并下载 PDF。\n"
    ),
    SkillPreview(
        name: "审查意见答复",
        path: "~/.agents/skills/oa-response/SKILL.md",
        markdown: "# 审查意见答复\n\n辅助撰写 OA 答复。\n"
    )
]

#Preview {
    SkillGalleryView()
        .frame(width: 900, height: 600)
}
