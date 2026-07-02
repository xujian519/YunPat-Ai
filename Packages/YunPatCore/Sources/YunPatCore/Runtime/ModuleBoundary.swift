import Foundation

// MARK: - Module Boundary Documentation

/// 对标 Tokio 多 crate 工作空间哲学的模块边界文档
///
/// 当前 YunPatCore 子目录按职责划分为以下逻辑域：
///
/// ```
/// YunPatCore/
/// │
/// ├── Loop/           → Agent 引擎域
/// │   ├── LoopEngine.swift        协议定义
/// │   ├── LoopState.swift         状态机 + 配置
/// │   ├── AgentLoopEngine.swift   通用 Agent 循环
/// │   ├── PatentLoopEngine.swift  专利五步循环
/// │   ├── StuckGuard.swift        循环守卫 + 陷入检测
/// │   ├── SubAgentEngine.swift    子代理扇出
/// │   └── ToolDispatch.swift      工具分派表
/// │
/// ├── Runtime/        → 运行时域 (Phase 1 新增)
/// │   ├── RuntimeConfig.swift     集中配置 (对标 Tokio config)
/// │   ├── CoopScheduler.swift     协作调度 (对标 Tokio coop)
/// │   ├── AgentMetrics.swift      无锁指标 (对标 Tokio metrics)
/// │   ├── AgentScheduler.swift    调度器协议 + Mock (对标 Tokio sync)
/// │   └── ToolCallState.swift     工具调用位标志状态机 (对标 Tokio State)
/// │
/// ├── Context/        → 上下文域
/// │   ├── ContextEngine.swift     上下文构建 + 注入
/// │   ├── CompactionWatermark.swift KV-stable 压缩
/// │   └── TokenEstimator.swift     token 估算
/// │
/// ├── Hooks/          → 钩子域
/// │   ├── HooksService.swift      Hook 执行引擎
/// │   └── AgentHook.swift         Hook 定义
/// │
/// ├── Memory/         → 记忆域
/// │   ├── MemoryEngine.swift      三层记忆模型
/// │   ├── MemoryStore.swift       工作记忆 + 情景记忆
/// │   ├── LLMMemoryStore.swift    LLM 文件记忆
/// │   └── MemoryTypes.swift       记忆类型定义
/// │
/// ├── Skill/          → 技能域
/// │   ├── SkillManager.swift      技能注册 + 生命周期
/// │   ├── SkillParser.swift       技能文件解析
/// │   └── SkillTypes.swift        技能类型定义
/// │
/// ├── Patent/         → 专利领域域
/// │   ├── SearchCommander.swift   检索命令编排
/// │   ├── ReasoningStrategy.swift 推理策略选择
/// │   ├── ChecklistEngine.swift   检查清单引擎
/// │   ├── FlexiblePlan.swift      动态计划调整
/// │   ├── LegalStateMachine.swift 法律状态机
/// │   └── FactBlackboard.swift    事实黑板
/// │
/// ├── Knowledge/      → 知识域
/// │   ├── WikiAdapter.swift       知识库适配器
/// │   ├── RuleEngine.swift        规则引擎
/// │   ├── FactExtractor.swift     事实提取
/// │   ├── EvaluationEngine.swift  评估引擎
/// │   ├── VaultObserver.swift     文件库监听
/// │   └── WikiTypes.swift         知识类型定义
/// │
/// ├── Quality/        → 质量域
/// │   ├── PatentRubric.swift      专利评分规范
/// │   ├── FactMarker.swift        事实标记
/// │   ├── TabooDetector.swift     禁忌词检测
/// │   ├── TwoPassDraft.swift      两阶段起草
/// │   └── TypedAction.swift       类型化动作
/// │
/// ├── Capability/     → 能力域
/// │   ├── CapabilityRegistry.swift  能力注册中心
/// │   ├── CapabilityDefinition.swift 能力定义
/// │   ├── ToolDefinition.swift       工具定义
/// │   └── CapabilityStats.swift      能力统计
/// │
/// ├── Trace/          → 追踪域
/// │   ├── TraceStore.swift        追踪存储
/// │   └── TraceCollector.swift    追踪收集
/// │
/// ├── SystemPrompt/   → 系统提示域
/// │   └── SystemPromptService.swift  系统提示服务
/// │
/// └── Utilities/      → 工具域 (Phase 2 新增)
///     ├── Bits.swift              位操作工具 (对标 Tokio util/bit)
///     ├── SyncWrapper.swift       线程安全桥接 (对标 Tokio util/sync_wrapper)
///     └── RandGenerator.swift     可种子 RNG (对标 Tokio util/rand)
/// ```
///
/// ## 未来拆分方案（对标 Tokio 多 crate 工作空间）
///
/// - `YunPatRuntime`  ← Loop + Runtime (Agent 引擎核心)
/// - `YunPatContext`  ← Context + Memory + SystemPrompt (上下文记忆)
/// - `YunPatPatent`   ← Patent + Knowledge + Quality (专利领域逻辑)
/// - `YunPatSkills`   ← Skill (技能系统)
/// - `YunPatCapability` ← Capability (能力/MCP 框架)
/// - `YunPatTest`     ← 测试工具 + Mock 实现 (对标 tokio-test)
///
/// ## 依赖关系约束（DAG，无循环）
///
/// ```mermaid
/// graph TD
///     Runtime --> Utilities
///     Loop --> Runtime
///     Context --> Memory
///     Hooks --> Loop
///     Patent --> Loop
///     Patent --> Knowledge
///     Knowledge --> Context
///     Quality --> Patent
///     Quality --> Knowledge
///     Capability --> Loop
///     Skill --> Loop
/// ```
///
public enum ModuleBoundary {
    /// 当前模块版本
    public static let version: String = "2.0-phase2"
    /// 模块拆分状态：Phase 2 文档化完成，实现级拆分待 Phase 2 最终验证
    public static let splitStatus: String = "documented"
}

// MARK: - Module Dependency Validator

/// 运行时模块依赖验证器（对标 Tokio 编译时 cfg 门控）
///
/// 在 DEBUG 模式下验证模块间无循环依赖、无不正确的跨域引用。
public enum ModuleValidator {
    /// 验证所有模块间依赖为 DAG
    public static func validate() -> [String] {
        let issues: [String] = []

        #if DEBUG
            // 在编译时，所有类型在同一个 module 中，此处为运行时占位
            // 真正验证在模块拆分后进行
        #endif

        return issues
    }
}

/// 模块依赖图的邻接表表示（文档化用途）
public enum ModuleDependencyGraph {
    public static let adjacency: [String: Set<String>] = [
        "Runtime": ["Utilities"],
        "Loop": ["Runtime", "Context", "YunPatNetworking"],
        "Context": ["Memory"],
        "Hooks": ["Loop"],
        "Patent": ["Loop", "Knowledge"],
        "Knowledge": ["Context"],
        "Quality": ["Patent", "Knowledge"],
        "Capability": ["Loop"],
        "Skill": ["Loop"],
        "Memory": [],
        "Trace": [],
        "SystemPrompt": [],
        "Utilities": []
    ]
}
