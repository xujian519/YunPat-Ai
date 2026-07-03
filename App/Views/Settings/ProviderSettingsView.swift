import SwiftUI
import YunPatNetworking

struct ProviderSettingsView: View {
    let modelRouter: ModelRouter

    @State private var openAIKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var deepseekKey: String = ""
    @State private var glmKey: String = ""
    @State private var registrationStatus: String = ""

    var body: some View {
        Form {
            Section("API Keys") {
                SecureField("OpenAI API Key", text: $openAIKey)
                    .accessibilityLabel("OpenAI API 密钥")
                    .accessibilityHint("输入 OpenAI API 密钥后自动保存到钥匙串")
                    .onChange(of: openAIKey) { _, newValue in
                        handleKeyChange(.openai, key: newValue)
                    }
                SecureField("Anthropic API Key", text: $anthropicKey)
                    .accessibilityLabel("Anthropic API 密钥")
                    .accessibilityHint("输入 Anthropic API 密钥后自动保存到钥匙串")
                    .onChange(of: anthropicKey) { _, newValue in
                        handleKeyChange(.anthropic, key: newValue)
                    }
                SecureField("DeepSeek API Key", text: $deepseekKey)
                    .accessibilityLabel("DeepSeek API 密钥")
                    .accessibilityHint("输入 DeepSeek API 密钥后自动保存到钥匙串")
                    .onChange(of: deepseekKey) { _, newValue in
                        handleKeyChange(.deepseek, key: newValue)
                    }
                SecureField("GLM API Key", text: $glmKey)
                    .accessibilityLabel("GLM API 密钥")
                    .accessibilityHint("输入 GLM API 密钥后自动保存到钥匙串")
                    .onChange(of: glmKey) { _, newValue in
                        handleKeyChange(.glm, key: newValue)
                    }
            }

            if !registrationStatus.isEmpty {
                Section {
                    Text(registrationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            openAIKey = CredentialStore.shared.apiKey(for: .openai) ?? ""
            anthropicKey = CredentialStore.shared.apiKey(for: .anthropic) ?? ""
            deepseekKey = CredentialStore.shared.apiKey(for: .deepseek) ?? ""
            glmKey = CredentialStore.shared.apiKey(for: .glm) ?? ""
        }
    }

    private func handleKeyChange(_ provider: ModelProvider, key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try CredentialStore.shared.store(provider: provider, apiKey: trimmed)
        } catch {
            registrationStatus = "Keychain 存储失败: \(error.localizedDescription)"
        }
        Task {
            await registerProvider(provider, key: trimmed)
        }
    }

    private func registerProvider(_ provider: ModelProvider, key: String) async {
        do {
            let backend = try makeBackend(provider: provider, key: key)
            await modelRouter.register(backend)
            await MainActor.run {
                registrationStatus = "\(provider.rawValue) 已注册，即时生效"
            }
        } catch {
            await MainActor.run {
                registrationStatus = "\(provider.rawValue) 注册失败: \(error.localizedDescription)"
            }
        }
    }

    private func makeBackend(provider: ModelProvider, key: String) throws -> any ModelBackend {
        switch provider {
        case .openai:
            return OpenAIProvider(apiKey: key)
        case .anthropic:
            return AnthropicProvider(apiKey: key)
        case .deepseek:
            guard let url = URL(string: "https://api.deepseek.com/v1") else {
                throw ProviderConfigError.invalidURL
            }
            return OpenAICompatProvider(apiKey: key, baseURL: url, provider: .deepseek)
        case .glm:
            guard let url = URL(string: "https://open.bigmodel.cn/api/paas/v4") else {
                throw ProviderConfigError.invalidURL
            }
            return OpenAICompatProvider(apiKey: key, baseURL: url, provider: .glm)
        default:
            throw ProviderConfigError.unsupportedProvider(provider.rawValue)
        }
    }
}

enum ProviderConfigError: Error, LocalizedError {
    case invalidURL
    case unsupportedProvider(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "URL 格式错误"
        case .unsupportedProvider(let name): "不支持的提供商: \(name)"
        }
    }
}
