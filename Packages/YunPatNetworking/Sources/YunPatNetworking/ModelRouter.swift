import Foundation

public actor ModelRouter {
    private var backends: [ModelProvider: ModelBackend] = [:]

    public init() {}

    public func register(_ backend: ModelBackend) {
        backends[backend.provider] = backend
    }

    public func route(provider: ModelProvider) -> ModelBackend? {
        backends[provider]
    }

    /// 发送聊天请求，自动脱敏云端请求并在响应流中反脱敏
    /// - Parameters:
    ///   - request: 聊天请求
    ///   - provider: 模型提供商
    ///   - caseId: 案件ID（可选，用于加载案件级敏感词表）
    /// - Returns: 已反脱敏的响应流
    public func chat(
        _ request: ChatRequest,
        provider: ModelProvider,
        caseId: String? = nil
    ) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        guard let backend = backends[provider] else {
            throw ModelRouterError.providerNotRegistered(provider)
        }

        // Step 1: 脱敏请求文本
        let (scrubbedRequest, scrubResult): (ChatRequest, ScrubResult) = try await PrivacyFilter.shared.scrub(
            request: request,
            provider: provider,
            caseId: caseId
        )

        // Step 2: fail-closed — 脱敏后仍有残留敏感信息则阻断
        guard !scrubResult.blocked else {
            throw ModelRouterError.scrubbingFailed(
                reason: "脱敏后仍检测到 \(scrubResult.detections.count) 处敏感信息"
            )
        }

        // Step 3: 发送脱敏后的请求
        let rawStream: AsyncThrowingStream<ChatChunk, Error> = backend.chat(scrubbedRequest)

        // Step 4: 在响应流中反脱敏（将占位符替换回原文）
        return PrivacyFilter.shared.unscrub(
            stream: rawStream,
            map: scrubResult.placeholderMap
        )
    }

    public var registeredProviders: [ModelProvider] {
        Array(backends.keys)
    }

    public var allBackends: [ModelProvider: any ModelBackend] {
        backends
    }
}

public enum ModelRouterError: Error {
    case providerNotRegistered(ModelProvider)
    case scrubbingFailed(reason: String)
}
