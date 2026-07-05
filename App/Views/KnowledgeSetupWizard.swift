import SwiftUI
import YunPatCore

/// 首次启动知识库配置引导向导
struct KnowledgeSetupWizard: View {
    @Binding var isPresented: Bool
    @State private var vaultPath: String = ""
    @State private var step: WizardStep = .welcome

    enum WizardStep {
        case welcome, detect, custom, done
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .padding(.top, 32)
                .accessibilityHidden(true)

            switch step {
            case .welcome:
                Text("欢迎使用 YunPat-Ai")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                Text("连接宝宸知识库以获得专利法规、审查指南和判例检索能力。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityLabel("连接宝宸知识库以获得专利法规、审查指南和判例检索能力。")

            case .detect:
                Text("检测知识库")
                    .font(.title3)
                    .accessibilityAddTraits(.isHeader)
                if !vaultPath.isEmpty {
                    Label("已找到: \(URL(fileURLWithPath: vaultPath).lastPathComponent)", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .accessibilityLabel("已找到知识库: \(URL(fileURLWithPath: vaultPath).lastPathComponent)")
                } else {
                    Text("未检测到 Obsidian vault。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("未检测到 Obsidian 知识库")
                }

            case .custom:
                Text("自定义路径")
                    .font(.title3)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    TextField("输入 Obsidian Vault 路径...", text: $vaultPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("知识库路径输入")
                    Button("浏览…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.prompt = "选择 Vault"
                        if panel.runModal() == .OK {
                            vaultPath = panel.url?.path ?? vaultPath
                        }
                    }
                    .accessibilityLabel("选择文件夹")
                    .accessibilityHint("打开文件选择器选择 Obsidian Vault 目录")
                }
                .frame(width: 400)

            case .done:
                Text("配置完成")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .accessibilityAddTraits(.isHeader)
                Text(vaultPath.isEmpty ? "跳过知识库配置。PatentLoop 降级为通用模式。" : "知识库已连接。PatentLoop 五步全部可用。")
                    .accessibilityLabel(vaultPath.isEmpty ? "跳过知识库配置。PatentLoop 降级为通用模式。" : "知识库已连接。PatentLoop 五步全部可用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // 导航按钮
            HStack(spacing: 16) {
                switch step {
                case .welcome:
                    Button("检测现有 Vault") {
                        detectVaults()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("检测现有知识库")
                    Button("自定义路径") { step = .custom }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("手动选择知识库路径")

                case .detect:
                    Button("使用此路径") { step = .done }
                        .buttonStyle(.borderedProminent)
                        .disabled(vaultPath.isEmpty)
                        .accessibilityLabel("使用检测到的知识库路径")
                    Button("自定义路径") { step = .custom }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("手动选择其他路径")

                case .custom:
                    Button("确认") { step = .done }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("确认知识库路径")
                    Button("返回") { step = .welcome }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("返回欢迎页")

                case .done:
                    Button("开始使用") {
                        saveVaultPath()
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("开始使用 YunPat-Ai")
                }
            }
            .padding(.bottom, 32)
        }
        .frame(width: 480, height: 420)
    }

    private func detectVaults() {
        step = .detect
        // 检测常见 iCloud Obsidian 路径
        let home: String = NSHomeDirectory()
        let candidates: [String] = [
            "\(home)/Library/Mobile Documents/iCloud~md~obsidian/Documents",
            "\(home)/Documents/Obsidian",
            "\(home)/Obsidian"
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            vaultPath = candidate
            break
        }
    }

    private func saveVaultPath() {
        if !vaultPath.isEmpty {
            UserDefaults.standard.set(vaultPath, forKey: "yunpat.vaultPath")
            Task {
                await KnowledgeBaseManager.shared.reset()
                try? await KnowledgeBaseManager.shared.configure(vaultPath: URL(filePath: vaultPath))
            }
        }
    }
}
