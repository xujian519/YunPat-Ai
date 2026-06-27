import Foundation

public final class CapabilityRegistry: @unchecked Sendable {
    private var capabilities: [CapabilityDefinition] = []
    private let lock = NSLock()

    public init() {}

    public func register(capability: CapabilityDefinition) {
        lock.lock(); defer { lock.unlock() }
        capabilities.append(capability)
    }

    public func listCapabilities() -> [CapabilityDefinition] {
        lock.lock(); defer { lock.unlock() }
        return capabilities
    }
}

extension CapabilityRegistry {
    public func registerBuiltinCapabilities() {
        register(capability: CapabilityDefinition(
            name: "core.chat",
            displayName: "对话",
            description: "通用 AI 对话能力",
            source: .builtin,
            permission: .always,
            metadata: CapabilityMetadata(
                costLevel: .low,
                requiresNetwork: true,
                isIdempotent: false,
                typicalUseCases: ["问答", "对话"]
            )
        ))
    }
}
