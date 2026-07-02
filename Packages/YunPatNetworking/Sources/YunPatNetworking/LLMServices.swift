import Foundation

// MARK: - LLM Services Container

/// 统一持有多个 LLM 后端服务实例的容器
///
/// 设计参考 Agent-main (macOS26/Agent) 的 TabLLMServices:
/// - 一次性构建所有已注册的 provider 后端
/// - 运行时按需选择 (if-let 链式选择)
/// - 支持运行时切换 provider（回退链场景）
public struct LLMServices: Sendable {

    /// 已注册的后端映射
    public let backends: [ModelProvider: any ModelBackend]

    /// 当前 active 的 provider
    public let primaryProvider: ModelProvider

    public init(backends: [ModelProvider: any ModelBackend], primaryProvider: ModelProvider = .deepseek) {
        self.backends = backends
        self.primaryProvider = primaryProvider
    }

    /// 根据 provider 获取对应后端
    public func backend(for provider: ModelProvider) -> (any ModelBackend)? {
        backends[provider]
    }

    /// 主后端
    public var primaryBackend: (any ModelBackend)? {
        backends[primaryProvider]
    }

    /// 从 ModelRouter actor 构建 LLMServices (async — 需要 await actor 属性)
    public static func build(from router: isolated ModelRouter, primaryProvider: ModelProvider = .deepseek)
        -> LLMServices {
        LLMServices(backends: router.allBackends, primaryProvider: primaryProvider)
    }
}
