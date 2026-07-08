import AppKit
import SwiftUI
import YunPatCore

/// PilotDeck 风格聊天输入栏
struct InputBar: View {
    @ObservedObject var chatManager: ChatManager
    @ObservedObject var tabManager: TabManager
    var onAttachFiles: () -> Void
    @FocusState private var isInputFocused: Bool
    @State private var showSkillPicker: Bool = false
    @State private var showAccessPopover: Bool = false
    @State private var availableSkills: [SkillManifest] = []

    var body: some View {
        VStack(spacing: 0) {
            TextField("告诉 YunPat-Ai 你想完成什么…", text: $chatManager.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(FontStyle.body)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .accessibilityLabel("消息输入框")
                .accessibilityHint("输入消息后按 ⌘+Enter 发送")
                .onSubmit {
                    if !sendDisabled {
                        Task { await chatManager.sendMessage(in: tabManager) }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)

            HStack(spacing: 0) {
                inputToolbar
                Spacer()
                sendButton
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(Color.appInputBarBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xl)
                        .stroke(isInputFocused ? Color.accentColor.opacity(0.5) : Color.appSeparator, lineWidth: 1)
                )
        )
        .padding(Spacing.md)
    }

    private var inputToolbar: some View {
        HStack(spacing: Spacing.sm) {
            ToolButton(icon: "sparkles", label: "智能体") {
                isInputFocused = true
                showSkillPicker.toggle()
            }
            .help("选择技能")
            .popover(isPresented: $showSkillPicker) {
                SkillPickerPopover(
                    skills: availableSkills,
                    onSelect: { skill in
                        chatManager.inputText = "/" + skill.name + " " + chatManager.inputText
                        showSkillPicker = false
                        isInputFocused = true
                    }
                )
                .frame(minWidth: 240, maxWidth: 300, minHeight: 200, maxHeight: 360)
                .task { await loadSkills() }
            }

            ToolButton(icon: "paperclip", label: nil) {
                onAttachFiles()
            }
            .help("附件文件")

            ToolButton(icon: "at", label: nil) {
                isInputFocused = true
                if !chatManager.inputText.hasPrefix("@") {
                    chatManager.inputText = "@" + chatManager.inputText
                }
            }
            .help("@提及")

            ToolButton(icon: "shield.fill", label: "完全访问权限", accent: true) {
                showAccessPopover.toggle()
            }
            .help("完全访问权限设置")
            .popover(isPresented: $showAccessPopover) {
                FullAccessPopover()
                    .frame(minWidth: 240, maxWidth: 280, minHeight: 140, maxHeight: 180)
            }
        }
    }

    private func loadSkills() async {
        let matches: [SkillMatch] = await SkillManager.shared.allSkills()
        availableSkills = matches.map { $0.skill.manifest }
    }

    private var sendButton: some View {
        Button {
            AppHaptic.generic()
            Task { await chatManager.sendMessage(in: tabManager) }
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: IconSize.toolbar, weight: .semibold))
                .foregroundStyle(sendDisabled ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.white))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(sendDisabled ? Color.appSurfaceTertiary : Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(sendDisabled)
        .keyboardShortcut(.return, modifiers: [.command])
        .accessibilityLabel("发送消息")
        .accessibilityHint("发送当前输入的消息")
        .help("⌘ + Enter 发送")
    }

    private var sendDisabled: Bool {
        let trimmed: String = chatManager.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return chatManager.isStreaming || trimmed.isEmpty
    }
}

struct ToolButton: View {
    let icon: String
    var label: String?
    var accent: Bool = false
    let action: () -> Void

    @State private var isHovered: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    var body: some View {
        Button(
            action: action,
            label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: icon)
                        .font(.system(size: IconSize.toolbar, weight: .medium))
                    if let label {
                        Text(label)
                            .font(FontStyle.callout)
                    }
                }
                .foregroundStyle(accent ? Color.orange : (isHovered ? Color.appTextPrimary : Color.appTextSecondary))
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .frame(minHeight: HitTarget.small + Spacing.xxs)
                .background(isHovered ? Color.appSurfaceTertiary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                .contentShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
            }
        )
        .buttonStyle(.plain)
        .onHover { hovering in
            withAccessibleAnimation(reduceMotion: reduceMotion, duration: AnimationDuration.fast) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Skill Picker Popover

private struct SkillPickerPopover: View {
    let skills: [SkillManifest]
    let onSelect: (SkillManifest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("选择技能")
                    .font(FontStyle.headline)
                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)

            Divider()

            if skills.isEmpty {
                EmptyStateView(
                    icon: "sparkles",
                    title: "暂无技能",
                    subtitle: "在设置中加载 .skill.md 文件",
                    action: nil
                )
                .padding(.vertical, Spacing.md)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(skills, id: \.name) { skill in
                            Button {
                                onSelect(skill)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(skill.displayName)
                                            .font(FontStyle.callout)
                                            .foregroundStyle(.primary)
                                        if !skill.description.isEmpty {
                                            Text(skill.description)
                                                .font(FontStyle.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(skill.description)
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
            }
        }
    }
}

// MARK: - Full Access Popover

private struct FullAccessPopover: View {
    @State private var isTrusted: Bool = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "shield.fill")
                    .foregroundStyle(isTrusted ? .green : .orange)
                Text("完全访问权限")
                    .font(FontStyle.headline)
                Spacer()
            }

            Text(isTrusted
                ? "辅助功能权限已授予，桌面自动化可用。"
                : "需要授予辅助功能权限以使用桌面自动化、截图等工具。")
                .font(FontStyle.caption)
                .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button(isTrusted ? "重新检查" : "打开系统设置…") {
                    if isTrusted {
                        isTrusted = AXIsProcessTrusted()
                    } else {
                        openAccessibilityPreferences()
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(Spacing.sm)
    }

    private func openAccessibilityPreferences() {
        let settingsURL: String = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
