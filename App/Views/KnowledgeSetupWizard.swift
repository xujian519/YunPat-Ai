import SwiftUI

/// 首次启动知识库配置引导向导
struct KnowledgeSetupWizard: View {
    @Binding var isPresented: Bool
    @State private var vaultPath = ""
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

            switch step {
            case .welcome:
                Text("欢迎使用 YunPat-Ai")
                    .font(.title2)
                Text("连接宝宸知识库以获得专利法规、审查指南和判例检索能力。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

            case .detect:
                Text("检测知识库")
                    .font(.title3)
                if !vaultPath.isEmpty {
                    Label("已找到: \(URL(fileURLWithPath: vaultPath).lastPathComponent)", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Text("未检测到 Obsidian vault。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .custom:
                Text("自定义路径")
                    .font(.title3)
                HStack {
                    TextField("输入 Obsidian Vault 路径...", text: $vaultPath)
                        .textFieldStyle(.roundedBorder)
                    Button("浏览…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.prompt = "选择 Vault"
                        if panel.runModal() == .OK {
                            vaultPath = panel.url?.path ?? vaultPath
                        }
                    }
                }
                .frame(width: 400)

            case .done:
                Text("配置完成")
                    .font(.title3)
                    .foregroundStyle(.green)
                Text(vaultPath.isEmpty ? "跳过知识库配置。PatentLoop 降级为通用模式。" : "知识库已连接。PatentLoop 五步全部可用。")
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
                    Button("自定义路径") { step = .custom }
                        .buttonStyle(.bordered)

                case .detect:
                    Button("使用此路径") { step = .done }
                        .buttonStyle(.borderedProminent)
                        .disabled(vaultPath.isEmpty)
                    Button("自定义路径") { step = .custom }
                        .buttonStyle(.bordered)

                case .custom:
                    Button("确认") { step = .done }
                        .buttonStyle(.borderedProminent)
                    Button("返回") { step = .welcome }
                        .buttonStyle(.bordered)

                case .done:
                    Button("开始使用") {
                        saveVaultPath()
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.bottom, 32)
        }
        .frame(width: 480, height: 420)
    }

    private func detectVaults() {
        step = .detect
        // 检测常见 iCloud Obsidian 路径
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/Library/Mobile Documents/iCloud~md~obsidian/Documents",
            "\(home)/Documents/Obsidian",
            "\(home)/Obsidian",
        ]
        for c in candidates {
            if FileManager.default.fileExists(atPath: c) {
                vaultPath = c
                break
            }
        }
    }

    private func saveVaultPath() {
        if !vaultPath.isEmpty {
            UserDefaults.standard.set(vaultPath, forKey: "yunpat.vaultPath")
        }
    }
}
