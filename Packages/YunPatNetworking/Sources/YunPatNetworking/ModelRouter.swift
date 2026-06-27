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

    public func chat(_ request: ChatRequest, provider: ModelProvider) async throws -> AsyncThrowingStream<ChatChunk, Error> {
        guard let backend = backends[provider] else {
            throw ModelRouterError.providerNotRegistered(provider)
        }
        return backend.chat(request)
    }

    public var registeredProviders: [ModelProvider] {
        Array(backends.keys)
    }
}

public enum ModelRouterError: Error {
    case providerNotRegistered(ModelProvider)
}
