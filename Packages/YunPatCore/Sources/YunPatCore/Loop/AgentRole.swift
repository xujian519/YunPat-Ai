import Foundation
import YunPatNetworking

// MARK: - AgentRole

/// 子代理角色 — 预设系统提示、工具组、迭代限制
///
/// 将常见的代理配置模式化为角色，避免每次 spawn 都手动指定全部参数。
///
/// ```swift
/// // 按角色生成 — 自动注入系统提示和工具组
/// await engine.spawn(role: .searcher, task: "查找 CN123 相关专利",
///                    modelRouter: router, provider: .deepseek)
/// ```
///
/// 也支持自定义角色：
/// ```swift
/// let myRole = AgentRole(
///     name: "翻译员",
///     systemPrompt: "你是专利文件翻译专家...",
///     toolGroupIDs: ["read_file", "write_file"]
/// )
/// ```
public struct AgentRole: Sendable {
    public let name: String
    public let systemPrompt: String
    public let toolGroupIDs: Set<String>?
    public let maxIterations: Int
    public let description: String

    public init(
        name: String,
        systemPrompt: String,
        toolGroupIDs: Set<String>? = nil,
        maxIterations: Int = 10,
        description: String = ""
    ) {
        self.name = name
        self.systemPrompt = systemPrompt
        self.toolGroupIDs = toolGroupIDs
        self.maxIterations = maxIterations
        self.description = description
    }

    /// 组装完整 prompt（系统提示 + 任务）
    public func makePrompt(task: String) -> String {
        "\(systemPrompt)\n\n---\n任务: \(task)"
    }
}

// MARK: - 预设角色

extension AgentRole {

    /// 检索员 — 专利/文献多源检索
    public static let searcher: AgentRole = AgentRole(
        name: "searcher",
        systemPrompt: """
            你是专利检索专家。使用 patent_search 和 knowledge_search 工具从多个来源查找相关专利和文献。
            返回结构化的检索结果，包括专利号、标题、相关度评分。
            优先使用精确的专利号或关键词检索，必要时组合布尔检索式。
            """,
        toolGroupIDs: ["patent_search", "knowledge_search", "read_file", "list_files"],
        maxIterations: 5,
        description: "专利/文献多源检索"
    )

    /// 分析师 — 技术特征对比分析
    public static let analyst: AgentRole = AgentRole(
        name: "analyst",
        systemPrompt: """
            你是专利技术分析专家。分析专利权利要求的技术特征、创新点和保护范围。
            对比不同专利的技术方案，识别相同/类似/不同的技术特征。
            输出结构化的特征对比表和创新点摘要。
            """,
        toolGroupIDs: ["read_file", "knowledge_search", "list_files", "search_files"],
        maxIterations: 8,
        description: "技术特征对比分析"
    )

    /// 起草员 — 权利要求/说明书起草
    public static let drafter: AgentRole = AgentRole(
        name: "drafter",
        systemPrompt: """
            你是专利文书起草专家。根据技术交底书起草权利要求和说明书。
            确保权利要求清楚、完整、得到说明书支持。独立权利要求应合理概括发明实质。
            从属权利要求应逐步限定，形成合理的保护层次。
            """,
        toolGroupIDs: ["read_file", "write_file", "edit", "knowledge_search", "list_files"],
        maxIterations: 15,
        description: "权利要求/说明书起草"
    )

    /// 审阅员 — 审查意见答复/OA 分析
    public static let reviewer: AgentRole = AgentRole(
        name: "reviewer",
        systemPrompt: """
            你是专利审查意见答复专家。分析审查意见中指出的问题（新颖性/创造性/清楚性等）。
            制定答复策略：修改权利要求、提供反驳论据、引用对比文件。
            输出结构化的答复方案，包括修改建议和论证逻辑。
            """,
        toolGroupIDs: ["read_file", "patent_search", "knowledge_search", "list_files"],
        maxIterations: 8,
        description: "审查意见答复/OA 分析"
    )

    /// 所有预设角色
    public static let allPresets: [AgentRole] = [.searcher, .analyst, .drafter, .reviewer]
}

// MARK: - SubAgentEngine + AgentRole

extension SubAgentEngine {

    /// 按角色生成子代理 — 自动注入角色系统提示、工具组和迭代限制
    ///
    /// ```swift
    /// await engine.spawn(role: .searcher, task: "查找 CN123 相关专利",
    ///                    modelRouter: router, provider: .deepseek)
    /// ```
    @discardableResult
    public func spawn(
        role: AgentRole,
        task: String,
        projectFolder: String = "",
        modelRouter: ModelRouter,
        provider: ModelProvider
    ) async -> String {
        await spawn(
            name: role.name,
            prompt: role.makePrompt(task: task),
            projectFolder: projectFolder,
            maxIterations: role.maxIterations,
            toolGroupIDs: role.toolGroupIDs,
            modelRouter: modelRouter,
            provider: provider
        )
    }

    /// 按角色批量生成子代理
    public func spawnBatch(
        roles: [(role: AgentRole, task: String)],
        projectFolder: String = "",
        modelRouter: ModelRouter,
        provider: ModelProvider
    ) async -> [String] {
        var results: [String] = []
        for item in roles {
            let msg: String = await spawn(
                role: item.role,
                task: item.task,
                projectFolder: projectFolder,
                modelRouter: modelRouter,
                provider: provider
            )
            results.append(msg)
        }
        return results
    }
}
