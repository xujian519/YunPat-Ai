import SwiftUI
import YunPatCore
import YunPatNetworking

/// 标签设置面板：工作目录 / 模型选择 / 工具管理 / 记忆管理
struct TabSettingsView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var chatManager: ChatManager
    @Binding var isPresented: Bool

    @State private var workspacePath = ""
    @State private var selectedModel = ""
    @State private var enabledTools: Set<String> = ["read_file", "write_file", "execute_shell"]
    @State private var memoryMode: MemoryMode = .session
    @State private var maxTokenBudget = 3000

    enum MemoryMode: String, CaseIterable {
        case session = "仅会话"
        case caseContext = "案件级"
        case fullArchive = "完整归档"
    }

    private var activeTab: ChatTab? {
        guard let id = tabManager.activeTabID else { return nil }
        return tabManager.tabs.first(where: { $0.id == id })
    }

    private let availableModels = [
        ("deepseek-chat", "DeepSeek V3", "经济实惠，综合能力强"),
        ("deepseek-reasoner", "DeepSeek R1", "强推理，适合复杂法律分析"),
        ("gpt-4o", "GPT-4o", "OpenAI 旗舰，多模态"),
        ("claude-sonnet-4-20250514", "Claude Sonnet 4", "长上下文，200K tokens"),
        ("glm-4", "GLM-4", "智谱，中英双语"),
    ]

    private let availableTools: [(String, String, String)] = [
        ("read_file", "读取文件", "doc.text"),
        ("write_file", "写入文件", "doc.badge.plus"),
        ("execute_shell", "Shell 执行", "terminal"),
        ("patent_search", "专利检索", "magnifyingglass"),
        ("legal_status_query", "法律状态查询", "building.columns"),
        ("knowledge_search", "知识库检索", "books.vertical"),
        ("list_files", "列出文件", "folder"),
        ("search_files", "搜索文件", "doc.text.magnifyingglass"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("标签设置")
                    .font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 工作目录
                    Group {
                        Text("📁 工作目录").font(.subheadline).bold()
                        HStack {
                            TextField(activeTab?.workspacePath?.path ?? "~/YunPat/workspaces/", text: $workspacePath)
                                .textFieldStyle(.roundedBorder)
                            Button("浏览…") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                if panel.runModal() == .OK {
                                    workspacePath = panel.url?.path ?? workspacePath
                                }
                            }
                        }
                    }

                    Divider()

                    // 模型选择
                    Group {
                        Text("🧠 模型选择").font(.subheadline).bold()
                        Picker("模型", selection: $selectedModel) {
                            ForEach(availableModels, id: \.0) { m in
                                VStack(alignment: .leading) {
                                    Text(m.1).font(.caption)
                                    Text(m.2).font(.caption2).foregroundStyle(.secondary)
                                }
                                .tag(m.0)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        HStack {
                            Text("Token 预算上限")
                            Spacer()
                            TextField("", value: $maxTokenBudget, format: .number)
                                .frame(width: 80)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Divider()

                    // 工具管理
                    Group {
                        Text("🔧 工具管理").font(.subheadline).bold()
                        ForEach(availableTools, id: \.0) { tool in
                            Toggle(isOn: Binding(
                                get: { enabledTools.contains(tool.0) },
                                set: { enabled in
                                    if enabled { enabledTools.insert(tool.0) }
                                    else { enabledTools.remove(tool.0) }
                                }
                            )) {
                                HStack {
                                    Image(systemName: tool.2)
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading) {
                                        Text(tool.1).font(.caption)
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    // 记忆管理
                    Group {
                        Text("💾 记忆管理").font(.subheadline).bold()
                        Picker("记忆模式", selection: $memoryMode) {
                            ForEach(MemoryMode.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Button("立即蒸馏当前会话") {
                            // trigger consolidation
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                    .buttonStyle(.bordered)
                Button("保存") {
                    applySettings()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 380, height: 560)
    }

    private func applySettings() {
        guard let idx = tabManager.tabs.firstIndex(where: { $0.id == activeTab?.id }) else { return }
        if !workspacePath.isEmpty {
            tabManager.tabs[idx].workspacePath = URL(fileURLWithPath: workspacePath)
        }
        if !selectedModel.isEmpty {
            tabManager.tabs[idx].loopModel = selectedModel
        }
    }
}
