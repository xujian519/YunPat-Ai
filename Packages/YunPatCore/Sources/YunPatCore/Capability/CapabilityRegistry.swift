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
            name: "core.chat", displayName: "对话", description: "通用 AI 对话能力",
            source: .builtin, permission: .always,
            metadata: CapabilityMetadata(costLevel: .low, requiresNetwork: true, isIdempotent: false, typicalUseCases: ["问答", "对话"])))
        register(capability: CapabilityDefinition(
            name: "knowledge.search", displayName: "知识库检索",
            description: "从宝宸知识库检索专利法规、审查指南、判例",
            source: .builtin, permission: .always,
            metadata: CapabilityMetadata(costLevel: .free, requiresNetwork: false, isIdempotent: true, typicalUseCases: ["法规查询", "案例检索"])))
        register(capability: CapabilityDefinition(
            name: "desktop.shell", displayName: "Shell 执行",
            description: "执行 shell 命令（白名单）", source: .builtin, permission: .perSession,
            metadata: CapabilityMetadata(costLevel: .free, requiresNetwork: false, isIdempotent: false, typicalUseCases: ["脚本执行", "git 操作"])))
        register(capability: CapabilityDefinition(
            name: "desktop.file", displayName: "文件操作",
            description: "读写工作目录文件（路径隔离）", source: .builtin, permission: .perSession,
            metadata: CapabilityMetadata(costLevel: .free, requiresNetwork: false, isIdempotent: false, typicalUseCases: ["文件读取", "文件写入"])))
        register(capability: CapabilityDefinition(
            name: "desktop.automation", displayName: "桌面自动化",
            description: "操控 Mac 应用（AXorcist Accessibility API）", source: .builtin, permission: .perCall,
            metadata: CapabilityMetadata(costLevel: .low, requiresNetwork: false, isIdempotent: false, typicalUseCases: ["应用操控", "UI 读取"])))
        register(capability: CapabilityDefinition(
            name: "sandbox.execute", displayName: "沙箱代码执行",
            description: "在隔离 VM 中执行代码（macOS 26+）", source: .builtin, permission: .always,
            metadata: CapabilityMetadata(costLevel: .free, requiresNetwork: false, isIdempotent: true, typicalUseCases: ["代码执行", "运行脚本"])))
    }
}
