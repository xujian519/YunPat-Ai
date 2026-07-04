import SwiftUI
import YunPatNetworking

struct ProviderSettingsView: View {
    let modelRouter: ModelRouter

    @State private var apiKeys: [ModelProvider: String] = [:]
    @State private var baseURLs: [ModelProvider: String] = [:]
    @State private var registrationStatus: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("云端服务") {
                    ForEach(ModelProvider.allCloud, id: \.self) { provider in
                        providerRow(provider)
                    }
                }

                Section("本地模型") {
                    ForEach(ModelProvider.allLocal, id: \.self) { provider in
                        providerRow(provider)
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
            .formStyle(.grouped)
        }
        .frame(minWidth: 520, minHeight: 600)
        .onAppear(perform: loadCredentials)
    }

    @ViewBuilder
    private func providerRow(_ provider: ModelProvider) -> some View {
        let def = ProviderDefinition.definition(for: provider)
        VStack(alignment: .leading, spacing: 6) {
            Label(def.displayName, systemImage: def.icon)
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                SecureField("API Key", text: apiKeyBinding(for: provider))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .labelsHidden()

                if provider != .mlx {
                    Button {
                        if let url = def.docURL, let link = URL(string: url) {
                            NSWorkspace.shared.open(link)
                        }
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("获取 API Key")
                }
            }

            if def.defaultBaseURL.isEmpty == false {
                HStack(spacing: 4) {
                    Text("端点")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 30, alignment: .trailing)
                    TextField("Base URL", text: baseURLBinding(for: provider))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .labelsHidden()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func apiKeyBinding(for provider: ModelProvider) -> Binding<String> {
        Binding(
            get: { apiKeys[provider] ?? "" },
            set: { newValue in
                apiKeys[provider] = newValue
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                do {
                    try CredentialStore.shared.store(provider: provider, apiKey: trimmed)
                } catch {
                    registrationStatus = "Keychain 存储失败: \(error.localizedDescription)"
                }
                Task { await registerProvider(provider, key: trimmed) }
            }
        )
    }

    private func baseURLBinding(for provider: ModelProvider) -> Binding<String> {
        Binding(
            get: { baseURLs[provider] ?? ProviderDefinition.definition(for: provider).defaultBaseURL },
            set: { baseURLs[provider] = $0 }
        )
    }

    private func loadCredentials() {
        for provider in ModelProvider.allCases {
            apiKeys[provider] = CredentialStore.shared.apiKey(for: provider) ?? ""
            baseURLs[provider] = ProviderDefinition.definition(for: provider).defaultBaseURL
        }
    }

    private func registerProvider(_ provider: ModelProvider, key: String) async {
        do {
            let backend = try makeBackend(provider: provider, key: key)
            await modelRouter.register(backend)
            await MainActor.run {
                registrationStatus = "\(ProviderDefinition.definition(for: provider).displayName) 已注册，即时生效"
            }
        } catch {
            let name: String = ProviderDefinition.definition(for: provider).displayName
            await MainActor.run {
                registrationStatus = "\(name) 注册失败: \(error.localizedDescription)"
            }
        }
    }

    private func makeBackend(provider: ModelProvider, key: String) throws -> any ModelBackend {
        let def = ProviderDefinition.definition(for: provider)
        switch provider {
        case .openai:
            return OpenAIProvider(apiKey: key)
        case .anthropic:
            return AnthropicProvider(apiKey: key)
        case .mlx:
            return OMLXBackend()
        case .ollama:
            let url: URL = urlForProvider(provider, def: def)
            return OpenAICompatProvider(apiKey: key, baseURL: url, provider: .ollama)
        default:
            let url: URL = urlForProvider(provider, def: def)
            return OpenAICompatProvider(apiKey: key, baseURL: url, provider: provider)
        }
    }
    private static let fallbackURL: URL = {
        let urlString: String = "https://api.openai.com/v1"
        guard let url = URL(string: urlString) else { preconditionFailure("Invalid URL: \(urlString)") }
        return url
    }()

    private func urlForProvider(_ provider: ModelProvider, def: ProviderDefinition) -> URL {
        let urlString: String = baseURLs[provider] ?? def.defaultBaseURL
        guard let url = URL(string: urlString) else {
            return Self.fallbackURL
        }
        return url
    }
}

enum ProviderConfigError: Error, LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL: "URL 格式错误"
        }
    }
}
