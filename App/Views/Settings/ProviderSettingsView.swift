import SwiftUI
import YunPatNetworking

struct ProviderSettingsView: View {
    @State private var openAIKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var deepseekKey: String = ""
    @State private var glmKey: String = ""

    var body: some View {
        Form {
            Section("API Keys") {
                SecureField("OpenAI API Key", text: $openAIKey)
                    .onChange(of: openAIKey) { _, newValue in
                        try? CredentialStore.shared.store(provider: .openai, apiKey: newValue)
                    }
                SecureField("Anthropic API Key", text: $anthropicKey)
                    .onChange(of: anthropicKey) { _, newValue in
                        try? CredentialStore.shared.store(provider: .anthropic, apiKey: newValue)
                    }
                SecureField("DeepSeek API Key", text: $deepseekKey)
                    .onChange(of: deepseekKey) { _, newValue in
                        try? CredentialStore.shared.store(provider: .deepseek, apiKey: newValue)
                    }
                SecureField("GLM API Key", text: $glmKey)
                    .onChange(of: glmKey) { _, newValue in
                        try? CredentialStore.shared.store(provider: .glm, apiKey: newValue)
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
}
