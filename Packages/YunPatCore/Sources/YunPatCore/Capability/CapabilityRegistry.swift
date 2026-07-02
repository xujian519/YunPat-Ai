import Foundation

public actor CapabilityRegistry {
    private var capabilities: [CapabilityDefinition] = []
    public init() {}
    public func register(capability: CapabilityDefinition) {
        capabilities.append(capability)
    }
    public func listCapabilities() -> [CapabilityDefinition] {
        capabilities
    }
}

extension CapabilityRegistry {
    public func registerBuiltinCapabilities() {
        register(
            capability: CapabilityDefinition(
                name: "core.chat", displayName: "对话", description: "通用 AI 对话能力",
                source: .builtin, permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .low, requiresNetwork: true, isIdempotent: false, typicalUseCases: ["问答", "对话"]),
                toolNames: ["todo", "complete", "clarify"]))
        register(
            capability: CapabilityDefinition(
                name: "desktop.file", displayName: "文件操作",
                description: "读写工作目录文件（路径隔离）", source: .builtin, permission: .perSession,
                metadata: CapabilityMetadata(
                    costLevel: .free, requiresNetwork: false, isIdempotent: false, typicalUseCases: ["文件读取", "文件写入"]),
                toolNames: [
                    "read_file", "write_file", "list_files", "search_files", "file_undo", "file_operation_history"
                ]))
        register(
            capability: CapabilityDefinition(
                name: "desktop.shell", displayName: "Shell 执行",
                description: "执行 shell 命令（白名单保护）", source: .builtin, permission: .perSession,
                metadata: CapabilityMetadata(
                    costLevel: .free, requiresNetwork: false, isIdempotent: false, typicalUseCases: ["脚本执行", "git 操作"]),
                toolNames: ["execute_shell"]))
        register(
            capability: CapabilityDefinition(
                name: "patent.search", displayName: "专利检索",
                description: "在 Google Patents / CNIPA 检索专利文献", source: .builtin, permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .low, requiresNetwork: true, isIdempotent: true, typicalUseCases: ["专利检索", "对比文件查找"]),
                toolNames: ["patent_search", "legal_status_query"]))
        register(
            capability: CapabilityDefinition(
                name: "knowledge.search", displayName: "知识库检索",
                description: "从宝宸知识库检索专利法规、审查指南、判例", source: .builtin, permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .free, requiresNetwork: false, isIdempotent: true, typicalUseCases: ["法规查询", "案例检索"]),
                toolNames: ["knowledge_search"]))
        register(
            capability: CapabilityDefinition(
                name: "desktop.automation", displayName: "桌面自动化",
                description: "操控 Mac 应用（AXorcist Accessibility API）", source: .builtin, permission: .perCall,
                metadata: CapabilityMetadata(
                    costLevel: .low, requiresNetwork: false, isIdempotent: false, typicalUseCases: ["应用操控", "UI 读取"]),
                toolNames: []))
        register(
            capability: CapabilityDefinition(
                name: "meta.discovery", displayName: "能力发现",
                description: "发现和加载可用能力与工具", source: .builtin, permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .free, requiresNetwork: false, isIdempotent: true, typicalUseCases: ["能力查询"]),
                toolNames: ["capabilities_discover", "capabilities_load", "list_tools"]))
    }
}

// MARK: - Tool Usage Guide Loading

extension CapabilityRegistry {
    /// 根据工具名加载对应的 TOOL.md 内容
    /// 优先从 Bundle 加载，回退到文件系统路径（开发/测试环境）
    public func usageGuide(for toolName: String) -> String? {
        // 尝试 Bundle (SPM resources 模式)
        if let url = Bundle(for: CapabilityRegistry.self)
            .url(forResource: toolName, withExtension: "md", subdirectory: "Tools/Docs"),
            let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        // 回退到 #filePath 相对路径（源码树开发模式）
        let sourceDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tools/Docs")
        let fileURL = sourceDir.appendingPathComponent("\(toolName).md")
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }
}
