import Foundation

// MARK: - Runtime Configuration

/// 对标 Tokio Builder + Config 分离模式的运行时配置
///
/// 所有运行时行为参数集中管理，支持 JSON 序列化持久化到 `~/.yunpat/config.json`。
/// 使用 `RuntimeConfigBuilder` 构建，链式调用设置各项参数。
///
/// ```swift
/// let config = RuntimeConfigBuilder()
///     .maxIterations(100)
///     .coopBudget(256)
///     .build()
/// ```
public struct RuntimeConfig: Sendable, Codable, Equatable {

    // ── Agent 循环 ──
    /// 最大迭代次数
    public var maxIterations: Int
    /// 每 N 次迭代检查中断/消息
    public var eventInterval: Int
    /// 协作调度预算（每次工具调用消耗 1，耗尽后主动 yield）
    public var coopBudget: Int

    // ── 子代理 ──
    /// 最大并发子代理数
    public var maxSubAgents: Int
    /// 单个子代理超时（秒）
    public var subAgentTimeout: TimeInterval
    /// 子代理失败重试次数
    public var subAgentRetry: Int

    // ── 工具执行 ──
    /// 单个工具调用超时（秒）
    public var toolTimeout: TimeInterval
    /// 工具调用失败最大重试次数
    public var maxToolRetries: Int
    /// 连续只读次数阈值（超过则触发 nudge）
    public var readOnlyStreakLimit: Int

    // ── Stuck Guard ──
    /// 编辑失败 nudge 阈值
    public var stuckNudgeThreshold: Int
    /// 编辑失败放弃阈值
    public var stuckGiveUpThreshold: Int

    // ── Context ──
    /// 压缩触发阈值（token 数）
    public var compactTokenThreshold: Int

    // ── 成本预算 ──
    /// 单次任务最大 token 预算（超出触发 overBudget 熔断，0 = 不限制）
    public var maxBudgetTokens: Int

    // ── 模型路由 ──
    /// 默认模型
    public var defaultModel: String
    /// 规划模型（复杂推理）
    public var planningModel: String
    /// 快速模型（分类 / 简单判断）
    public var fastModel: String

    // ── 调试 ──
    /// 是否启用详细日志
    public var verboseLogging: Bool

    // ── 存储路径（可选，默认 nil 表示使用各模块内置默认值） ──
    /// 知识库 vault 目录
    public var vaultPath: URL?
    /// 本地 embedding 模型路径
    public var embeddingModelPath: URL?
    /// 语义索引存储路径
    public var semanticIndexPath: URL?

    // ── 检索模式 ──
    /// 检索模式
    public var retrievalMode: RetrievalMode

    // MARK: - Init

    public init(
        maxIterations: Int = 50,
        eventInterval: Int = 10,
        coopBudget: Int = 128,
        maxSubAgents: Int = 3,
        subAgentTimeout: TimeInterval = 120,
        subAgentRetry: Int = 1,
        toolTimeout: TimeInterval = 30,
        maxToolRetries: Int = 2,
        readOnlyStreakLimit: Int = 10,
        stuckNudgeThreshold: Int = 2,
        stuckGiveUpThreshold: Int = 6,
        compactTokenThreshold: Int = 8000,
        maxBudgetTokens: Int = 200_000,
        defaultModel: String = "deepseek-chat",
        planningModel: String = "claude-opus",
        fastModel: String = "deepseek-chat",
        verboseLogging: Bool = false,
        vaultPath: URL? = nil,
        embeddingModelPath: URL? = nil,
        semanticIndexPath: URL? = nil,
        retrievalMode: RetrievalMode = .disabled
    ) {
        self.maxIterations = maxIterations
        self.eventInterval = eventInterval
        self.coopBudget = coopBudget
        self.maxSubAgents = maxSubAgents
        self.subAgentTimeout = subAgentTimeout
        self.subAgentRetry = subAgentRetry
        self.toolTimeout = toolTimeout
        self.maxToolRetries = maxToolRetries
        self.readOnlyStreakLimit = readOnlyStreakLimit
        self.stuckNudgeThreshold = stuckNudgeThreshold
        self.stuckGiveUpThreshold = stuckGiveUpThreshold
        self.compactTokenThreshold = compactTokenThreshold
        self.maxBudgetTokens = maxBudgetTokens
        self.defaultModel = defaultModel
        self.planningModel = planningModel
        self.fastModel = fastModel
        self.verboseLogging = verboseLogging
        self.vaultPath = vaultPath
        self.embeddingModelPath = embeddingModelPath
        self.semanticIndexPath = semanticIndexPath
        self.retrievalMode = retrievalMode
    }
}

// MARK: - Retrieval Mode

public enum RetrievalMode: String, Codable, Sendable, Equatable {
    case disabled
    case keyword
    case semantic
}

// MARK: - Builder

/// RuntimeConfig 构建器 — 链式调用的 Builder
///
/// 对标 Tokio `runtime::Builder`，所有 `func` 返回 `Self` 实现链式 DSL。
/// 不直接修改自身（值语义），通过 `var s = self` 模式返回新实例。
public struct RuntimeConfigBuilder: Sendable {
    private var config: RuntimeConfig = RuntimeConfig()

    public init() {}

    /// 设置最大迭代次数
    @discardableResult
    public func maxIterations(_ value: Int) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.maxIterations = value
        return copy
    }
    /// 设置事件检查间隔（迭代次数）
    @discardableResult
    public func eventInterval(_ value: Int) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.eventInterval = value
        return copy
    }
    /// 设置协作调度预算
    @discardableResult
    public func coopBudget(_ value: Int) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.coopBudget = value
        return copy
    }

    /// 设置最大并发子代理数
    @discardableResult
    public func maxSubAgents(_ value: Int) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.maxSubAgents = value
        return copy
    }
    /// 设置子代理超时（秒）
    @discardableResult
    public func subAgentTimeout(_ value: TimeInterval) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.subAgentTimeout = value
        return copy
    }
    /// 设置子代理失败重试次数
    @discardableResult
    public func subAgentRetry(_ value: Int) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.subAgentRetry = value
        return copy
    }

    /// 设置单个工具调用超时（秒）
    @discardableResult
    public func toolTimeout(_ value: TimeInterval) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.toolTimeout = value
        return copy
    }
    /// 设置工具调用失败最大重试次数
    @discardableResult
    public func maxToolRetries(_ value: Int) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.maxToolRetries = value
        return copy
    }
    /// 设置连续只读操作阈值（超过触发 nudge）
    @discardableResult
    public func readOnlyStreakLimit(_ value: Int) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.readOnlyStreakLimit = value
        return copy
    }

    /// 设置编辑失败 nudge 阈值
    @discardableResult
    public func stuckNudgeThreshold(_ value: Int) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.stuckNudgeThreshold = value
        return copy
    }
    /// 设置编辑失败放弃阈值
    @discardableResult
    public func stuckGiveUpThreshold(_ value: Int) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.stuckGiveUpThreshold = value
        return copy
    }

    /// 设置压缩触发阈值（token 数）
    @discardableResult
    public func compactTokenThreshold(_ value: Int) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.compactTokenThreshold = value
        return copy
    }

    /// 设置单次任务最大 token 预算（0 = 不限制）
    @discardableResult
    public func maxBudgetTokens(_ value: Int) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.maxBudgetTokens = value
        return copy
    }

    /// 设置默认模型
    @discardableResult
    public func defaultModel(_ value: String) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.defaultModel = value
        return copy
    }
    /// 设置规划模型（复杂推理）
    @discardableResult
    public func planningModel(_ value: String) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.planningModel = value
        return copy
    }
    /// 设置快速模型（简单分类/判断）
    @discardableResult
    public func fastModel(_ value: String) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.fastModel = value
        return copy
    }

    /// 设置是否启用详细日志
    @discardableResult
    public func verboseLogging(_ value: Bool) -> Self {
        var copy: RuntimeConfigBuilder = self
        copy.config.verboseLogging = value
        return copy
    }

    /// 构建最终配置
    public func build() -> RuntimeConfig { config }
}

// MARK: - Persistence

extension RuntimeConfig {

    /// 默认存储路径 `~/.yunpat/config.json`
    public static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".yunpat/config.json")
    }

    /// 加载配置，文件不存在则返回默认值
    public static func load(from path: URL = defaultPath) -> RuntimeConfig {
        guard let data = try? Data(contentsOf: path),
            let config = try? JSONDecoder().decode(RuntimeConfig.self, from: data)
        else { return RuntimeConfig() }
        return config
    }

    /// 从 UserDefaults 加载运行时配置（覆盖文件中加载的值）
    public static func loadFromUserDefaults() -> RuntimeConfig {
        let defaults: UserDefaults = UserDefaults.standard
        var config = RuntimeConfig.load()

        if let vaultPathStr = defaults.string(forKey: "yunpat.vaultPath") {
            config.vaultPath = URL(fileURLWithPath: vaultPathStr)
        }
        if let embeddingPathStr = defaults.string(forKey: "yunpat.embeddingModelPath") {
            config.embeddingModelPath = URL(fileURLWithPath: embeddingPathStr)
        }
        if let indexPathStr = defaults.string(forKey: "yunpat.semanticIndexPath") {
            config.semanticIndexPath = URL(fileURLWithPath: indexPathStr)
        }
        if let modeRaw = defaults.string(forKey: "yunpat.retrievalMode"),
           let mode = RetrievalMode(rawValue: modeRaw) {
            config.retrievalMode = mode
        }

        return config
    }

    /// 持久化配置到磁盘
    public func save(to path: URL = defaultPath) throws {
        let dir: URL = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data: Data = try JSONEncoder().encode(self)
        try data.write(to: path, options: .atomic)
    }
}
