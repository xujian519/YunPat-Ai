import SwiftUI
import YunPatCore
import YunPatNetworking

/// 标签设置面板：工作目录 / 模型选择 / 工具管理 / 记忆管理
struct TabSettingsView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var chatManager: ChatManager
    @Binding var isPresented: Bool

    @State private var workspacePath: String = ""
    @State private var selectedModel: String = ""
    @State private var enabledTools: Set<String> = ["read_file", "write_file", "execute_shell"]
    @State private var memoryMode: MemoryMode = .session
    @State private var maxTokenBudget: Int = 3000

    enum MemoryMode: String, CaseIterable {
        case session = "仅会话"
        case caseContext = "案件级"
        case fullArchive = "完整归档"
    }

    private var activeTab: ChatTab? {
        guard let id = tabManager.activeTabID else { return nil }
        return tabManager.tabs.first(where: { $0.id == id })
    }

    private let availableModels: [ModelOption] = [
        ModelOption(id: "deepseek-chat", name: "DeepSeek V3", note: "经济实惠，综合能力强"),
        ModelOption(id: "deepseek-reasoner", name: "DeepSeek R1", note: "强推理，适合复杂法律分析"),
        ModelOption(id: "gpt-4o", name: "GPT-4o", note: "OpenAI 旗舰，多模态"),
        ModelOption(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", note: "长上下文，200K tokens"),
        ModelOption(id: "glm-4", name: "GLM-4", note: "智谱，中英双语")
    ]

    private let availableTools: [ToolOption] = [
        ToolOption(id: "read_file", name: "读取文件", icon: "doc.text"),
        ToolOption(id: "write_file", name: "写入文件", icon: "doc.badge.plus"),
        ToolOption(id: "execute_shell", name: "Shell 执行", icon: "terminal"),
        ToolOption(id: "patent_search", name: "专利检索", icon: "magnifyingglass"),
        ToolOption(id: "legal_status_query", name: "法律状态查询", icon: "building.columns"),
        ToolOption(id: "knowledge_search", name: "知识库检索", icon: "books.vertical"),
        ToolOption(id: "list_files", name: "列出文件", icon: "folder"),
        ToolOption(id: "search_files", name: "搜索文件", icon: "doc.text.magnifyingglass")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("标签设置")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
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
                            ForEach(availableModels, id: \.id) { model in
                                VStack(alignment: .leading) {
                                    Text(model.name).font(.caption)
                                    Text(model.note).font(.caption2).foregroundStyle(.secondary)
                                }
                                .tag(model.id)
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
                        ForEach(availableTools, id: \.id) { tool in
                            Toggle(
                                isOn: Binding(
                                    get: { enabledTools.contains(tool.id) },
                                    set: { enabled in
                                        if enabled {
                                            enabledTools.insert(tool.id)
                                        } else {
                                            enabledTools.remove(tool.id)
                                        }
                                    }
                                )
                            ) {
                                HStack {
                                    Image(systemName: tool.icon)
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading) {
                                        Text(tool.name).font(.caption)
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
                            ForEach(MemoryMode.allCases, id: \.self) { model in
                                Text(model.rawValue).tag(model)
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

    private struct ModelOption {
        let id: String
        let name: String
        let note: String
    }

    private struct ToolOption {
        let id: String
        let name: String
        let icon: String
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
