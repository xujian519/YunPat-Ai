# YunPat-Ai 功能清单

> 更新日期: 2026-07-07
>
> **说明**: 专利检索/知识检索/法律状态查询工具采用依赖注入 (DI) 模式，需调用 `configurePatentSearch()/configureKnowledgeSearch()/configureLegalStatus()` 注入后端实现。App 启动时自动通过 `SearchCommander` 配置默认后端。未配置时将返回清晰的"未配置"错误提示。

| 功能 | 状态 | 文档 | 代码位置 |
|------|------|------|---------|
| **核心引擎** | | | |
| Agent 循环引擎 | Stable | `docs/ARCHITECTURE.md` §4 | `Packages/YunPatCore/Sources/YunPatCore/Loop/AgentLoopEngine.swift` |
| 子代理引擎 | Stable | `docs/ARCHITECTURE.md` §4 | `Packages/YunPatCore/Sources/YunPatCore/Loop/SubAgentEngine.swift` |
| 流程分类器 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/FlowClassifier.swift` |
| 卡死检测 (StuckGuard) | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/StuckGuard.swift` |
| **专利五步闭环 (PatentLoop)** | | | |
| Patent Loop 引擎 | Stable | `docs/ARCHITECTURE.md` §4 | `Packages/YunPatCore/Sources/YunPatCore/Loop/PatentLoopEngine.swift` |
| 专利工具循环 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/PatentToolLoop.swift` |
| 检索指挥器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/SearchCommander.swift` |
| 推理策略 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/ReasoningStrategy.swift` |
| 推理遍历器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/ReasoningWalker.swift` |
| **能力注册系统** | | | |
| Capability 注册表 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityRegistry.swift` |
| Capability 定义 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityDefinition.swift` |
| Capability 加载缓存 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityLoadBuffer.swift` |
| Capability Manifest | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityManifest.swift` |
| Capability 统计 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityStats.swift` |
| 工具定义 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Capability/ToolDefinition.swift` |
| **上下文引擎** | | | |
| 上下文引擎 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Context/ContextEngine.swift` |
| 上下文压缩水位 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Context/CompactionWatermark.swift` |
| 上下文摘要器 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Context/ContextSummarizer.swift` |
| Token 估算器 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Context/TokenEstimator.swift` |
| 上下文压缩策略 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Context/CompactionPolicy.swift` |
| 全量压缩器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Context/FullCompactor.swift` |
| **记忆系统** | | | |
| 记忆引擎 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryEngine.swift` |
| 记忆合并器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryConsolidator.swift` |
| 记忆读取路径 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryReadPath.swift` |
| 记忆写入路径 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryWritePath.swift` |
| 会话记忆 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Memory/SessionMemory.swift` |
| 记忆存储 (JSON) | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryStore.swift` |
| LLM 记忆存储 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Memory/LLMMemoryStore.swift` |
| 记忆数据库 (SQLite) | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Storage/MemoryDatabase.swift` |
| 记忆类型系统 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryTypes.swift` |
| 梦境审查服务 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Memory/DreamReviewService.swift` |
| 记忆审计服务 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryAuditService.swift` |
| **知识检索** | | | |
| Wiki 适配器 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/WikiAdapter.swift` |
| 规则引擎 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/RuleEngine.swift` |
| 事实提取器 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/FactExtractor.swift` |
| 评估引擎 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/EvaluationEngine.swift` |
| 语义索引 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/SemanticIndex.swift` |
| 向量搜索 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/VectorSearch.swift` |
| 混合检索器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/HybridRetriever.swift` |
| 内存向量索引 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/InMemoryVectorIndex.swift` |
| SQLite 向量索引 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/SQLiteVectorIndex.swift` |
| 查询路由器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/QueryRouter.swift` |
| 权威性评分器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/AuthorityScorer.swift` |
| 层级验证器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/TierVerifier.swift` |
| 关键词嵌入器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/KeywordEmbedder.swift` |
| MLX 嵌入提供者 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/MLXEmbeddingProvider.swift` |
| 嵌入提供者协议 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/EmbeddingProvider.swift` |
| 保险库观察者 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Knowledge/VaultObserver.swift` |
| **文档适配器** | | | |
| 文档适配器协议 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/DocumentAdapter/DocumentAdapter.swift` |
| 文档适配器提供者 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/DocumentAdapter/DocumentAdapterProvider.swift` |
| 文档适配器注册表 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/DocumentAdapter/DocumentAdapterRegistry.swift` |
| CSV 文档适配器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/DocumentAdapter/Adapters/CSVDocumentAdapter.swift` |
| Office 文档适配器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/DocumentAdapter/Adapters/OfficeDocumentAdapter.swift` |
| PDF 文档适配器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/DocumentAdapter/Adapters/PDFDocumentAdapter.swift` |
| 纯文本适配器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/DocumentAdapter/Adapters/PlainTextDocumentAdapter.swift` |
| 专利文档工具 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/DocumentAdapter/PatentDocumentTool.swift` |
| **专利法律知识** | | | |
| 专利法知识图谱 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/PatentLawKnowledgeGraph.swift` |
| 案件关系存储 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/CaseRelationStore.swift` |
| 案件规则加载器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/CaseRuleLoader.swift` |
| 要件清单引擎 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/ChecklistEngine.swift` |
| 事实黑板 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/FactBlackboard.swift` |
| 灵活方案 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/FlexiblePlan.swift` |
| 法律意图检测器 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/LegalIntentDetector.swift` |
| 法律状态机 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/LegalStateMachine.swift` |
| 框架引擎 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/FrameworkEngine.swift` |
| 模式学习器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/PatternLearner.swift` |
| PDF 渲染器 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Patent/PDFRenderer.swift` |
| **质量控制** | | | |
| 二次起草 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Quality/TwoPassDraft.swift` |
| 专利评分卡 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Quality/PatentRubric.swift` |
| 事实标记器 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Quality/FactMarker.swift` |
| 禁忌词检测 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Quality/TabooDetector.swift` |
| 类型化动作 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Quality/TypedAction.swift` |
| **工具系统** | | | |
| 类型化工具 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/TypedTool.swift` |
| 工具分发 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/ToolDispatch.swift` |
| 工具批量执行器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/ToolBatchExecutor.swift` |
| 专利搜索工具 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Tools/TypedPatentSearchTool.swift` |
| 知识搜索工具 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Tools/TypedKnowledgeSearchTool.swift` |
| 文件读取工具 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Tools/TypedReadFileTool.swift` |
| 桌面自动化工具 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/ToolDispatch+AXorcistTools.swift` |
| 文档工具 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/ToolDispatch+DocTools.swift` |
| 文件工具 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/ToolDispatch+FileTools.swift` |
| 专利工具 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/ToolDispatch+PatentTools.swift` |
| **隐私保护** | | | |
| 隐私过滤器 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/Privacy/PrivacyFilter.swift` |
| 路径安全 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Privacy/PathSecurity.swift` |
| 设备端分类器 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Privacy/OnDeviceClassifier.swift` |
| 敏感词注册表 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/Privacy/SensitiveTermsRegistry.swift` |
| **桌面自动化** | | | |
| 桌面自动化提供者 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Desktop/DesktopAutomationProvider.swift` |
| 文件操作日志 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Desktop/FileOperationLog.swift` |
| 文件快照存储 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Desktop/FileSnapshotStore.swift` |
| AXorcist 桥接 | Experimental | — | `Packages/YunPatDesktop/Sources/YunPatDesktop/AXorcistProvider.swift` |
| AppleScript 桥接 | Experimental | — | `Packages/YunPatDesktop/Sources/YunPatDesktop/AppleScriptBridge.swift` |
| Shell 执行器 | Experimental | — | `Packages/YunPatDesktop/Sources/YunPatDesktop/ShellExecutor.swift` |
| 文件操作器 | Experimental | — | `Packages/YunPatDesktop/Sources/YunPatDesktop/FileOperator.swift` |
| 安全门 | Experimental | — | `Packages/YunPatDesktop/Sources/YunPatDesktop/SecurityGate.swift` |
| 版本控制器 | Experimental | — | `Packages/YunPatDesktop/Sources/YunPatDesktop/VersionController.swift` |
| **网络 / 模型路由** | | | |
| LLM 服务层 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/LLMServices.swift` |
| 模型路由器 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/ModelRouter.swift` |
| 降级链服务 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/FallbackChainService.swift` |
| 速率限制器 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/RateLimiter.swift` |
| 凭证存储 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/CredentialStore.swift` |
| 安全凭证存储 | Experimental | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/SecureCredentialStore.swift` |
| 模型后端抽象 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/ModelBackend.swift` |
| Chat 请求 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/ChatRequest.swift` |
| Chat 分块 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/ChatChunk.swift` |
| 消息模型 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/Message.swift` |
| Usage 追踪 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/Usage.swift` |
| 网络策略 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/NetworkPolicy.swift` |
| Fixture 录制 | Experimental | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/FixtureRecorder.swift` |
| 路由引擎 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Routing/RoutingEngine.swift` |
| Token 预算服务 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Routing/TokenBudgetService.swift` |
| Token 使用存储 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Routing/TokenUsageStore.swift` |
| **后端提供者** | | | |
| Anthropic 提供者 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/Providers/AnthropicProvider.swift` |
| OpenAI 提供者 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/Providers/OpenAIProvider.swift` |
| OpenAI 兼容提供者 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/Providers/OpenAICompatProvider.swift` |
| OMLX 后端 | Experimental | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/Providers/OMLXBackend.swift` |
| **流式输出** | | | |
| 流式 Chat 分块 | Stable | — | `Packages/YunPatNetworking/Sources/YunPatNetworking/ChatChunk.swift` |
| 模型流式回调 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/AgentLoopEngine.swift` (processStream) |
| Tool Call 增量累积 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/AgentLoopEngine.swift` |
| **插件系统** | | | |
| 插件管理器 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/PluginManager.swift` |
| 插件加载器 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/PluginLoader.swift` |
| 插件上下文 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/PluginContext.swift` |
| 插件类型 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/PluginTypes.swift` |
| 插件校验器 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/PluginVerifier.swift` |
| 插件密钥 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/PluginSecret.swift` |
| **MCP 协议** | | | |
| MCP 客户端 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/MCPClient.swift` |
| MCP 服务端 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/MCPServer.swift` |
| MCP 传输 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/MCPTransport.swift` |
| HTTP MCP 传输 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/HTTPMCPTransport.swift` |
| 进程内 MCP 传输 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/InProcessMCPTransport.swift` |
| MCP 类型 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/MCPTypes.swift` |
| MCP 工具桥接 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/MCPToolBridge.swift` |
| MCP 配置加载器 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/MCPConfigLoader.swift` |
| **专利插件** | | | |
| 专利搜索插件 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/PatentSearchPlugin.swift` |
| 权利要求起草插件 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/ClaimDraftingPlugin.swift` |
| 专利翻译插件 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/PatentTranslatePlugin.swift` |
| 侵权分析插件 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/InfringementPlugin.swift` |
| OA 答复插件 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/OAResponsePlugin.swift` |
| 文档处理插件 | Experimental | — | `Packages/YunPatPlugins/Sources/YunPatPlugins/DocumentProcessorPlugin.swift` |
| **外部检索客户端** | | | |
| Google Patents 客户端 | Stable | — | `Packages/PatentClient/Sources/PatentClient/GooglePatentsClient.swift` |
| PSS 客户端 (官方) | Stable | — | `Packages/PatentClient/Sources/PatentClient/PssClient.swift` |
| **Sandbox** | | | |
| Sandbox 提供者 | Experimental | — | `Packages/YunPatSandbox/Sources/YunPatSandbox/SandboxProvider.swift` |
| **运行时 / 配置** | | | |
| 运行时配置 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Runtime/RuntimeConfig.swift` |
| 特性开关 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Runtime/FeatureFlags.swift` |
| Agent 调度器 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Runtime/AgentScheduler.swift` |
| 协作调度器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Runtime/CoopScheduler.swift` |
| 智能模型路由器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Runtime/SmartModelRouter.swift` |
| 模块边界 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Runtime/ModuleBoundary.swift` |
| 工具调用状态 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Runtime/ToolCallState.swift` |
| Agent 指标 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Runtime/AgentMetrics.swift` |
| 始终在线调度器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Runtime/AlwaysOnScheduler.swift` |
| Agent 角色 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/AgentRole.swift` |
| 循环状态 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/LoopState.swift` |
| 工具审计记录器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Loop/ToolAuditRecorder.swift` |
| **事件 / 追踪** | | | |
| 事件总线 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/EventBus/EventBus.swift` |
| 追踪收集器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Trace/TraceCollector.swift` |
| 追踪存储 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Trace/TraceStore.swift` |
| **成本追踪** | | | |
| 成本追踪器 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Cost/CostTracker.swift` |
| **技能系统** | | | |
| 技能管理器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Skill/SkillManager.swift` |
| 技能解析器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Skill/SkillParser.swift` |
| **SSR 防护** | | | |
| SSR 防护 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/SSR/SSRGuard.swift` |
| **持久化存储** | | | |
| 案件数据库 (SQLite) | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Storage/CaseDatabase.swift` |
| 降级存储 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Storage/DegradedStore.swift` |
| 存储收敛器 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Storage/StorageConverger.swift` |
| **Hook 系统** | | | |
| Agent Hook | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Hooks/AgentHook.swift` |
| Hook 服务 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Hooks/HooksService.swift` |
| **案件工作区** | | | |
| 案件工作区模型 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Workspace/CaseWorkspace.swift` |
| 案件工作区服务 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/Workspace/CaseWorkspaceService.swift` |
| 案件工作区存储 | Experimental | — | `Packages/YunPatCore/Sources/YunPatCore/Workspace/CaseWorkspaceStore.swift` |
| **系统提示** | | | |
| 系统提示服务 | Stable | — | `Packages/YunPatCore/Sources/YunPatCore/SystemPrompt/SystemPromptService.swift` |
| **macOS UI (SwiftUI)** | | | |
| 主内容视图 | Stable | — | `App/Views/ContentView.swift` |
| 对话视图 | Stable | — | `App/Views/ChatView.swift` |
| 标签栏内容 (TabStrip) | Stable | — | `App/Views/TabStripContent.swift` |
| 状态栏 | Stable | — | `App/Views/StatusBar.swift` |
| Tab 系统 | Stable | — | `App/Views/Tab.swift`, `App/Views/TabBar.swift` |
| 案件列表侧栏 | Stable | — | `App/Views/CaseListSidebar.swift` |
| 文档工作区 | Stable | — | `App/Views/DocumentWorkspace.swift` |
| 文件夹树视图 | Stable | — | `App/Views/FolderTreeView.swift` |
| 专利浏览器 | Stable | — | `App/Views/PatentBrowser.swift` |
| 注释解析器 | Stable | — | `App/Views/AnnotationParser.swift` |
| 协作面板 | Stable | — | `App/Views/CollaborationPanelView.swift` |
| 清单视图 | Stable | — | `App/Views/ChecklistView.swift` |
| 澄清弹窗 | Stable | — | `App/Views/ClarifyOverlay.swift` |
| 案件图谱视图 | Experimental | — | `App/Views/CaseGraphView.swift` |
| 知识设置向导 | Experimental | — | `App/Views/KnowledgeSetupWizard.swift` |
| 文档变更检测器 | Stable | — | `App/Views/DocumentChangeDetector.swift` |
| 窗口状态恢复 | Stable | — | `App/Views/WindowStateRestoration.swift` |
| 设计令牌 | Stable | — | `App/Views/DesignTokens.swift` |
| 空状态视图 | Stable | — | `App/Views/EmptyStateView.swift` |
| 表面修饰器 | Stable | — | `App/Views/SurfaceModifiers.swift` |
| 颜色系统 | Stable | — | `App/Views/Color+App.swift` |
| 内容视图修饰器 | Stable | — | `App/Views/ContentViewModifiers.swift` |
| 聊天欢迎视图 | Stable | — | `App/Views/Agent/ChatWelcomeView.swift` |
| 顶部模块栏 | Stable | — | `App/Views/Navigation/TopModuleBar.swift` |
| 项目列表侧栏 | Stable | — | `App/Views/Project/ProjectListSidebar.swift` |
| 路由仪表盘 | Experimental | — | `App/Views/Workspace/RoutingDashboardView.swift` |
| 记忆仪表盘 | Experimental | — | `App/Views/Workspace/MemoryDashboardView.swift` |
| 技能画廊 | Experimental | — | `App/Views/Workspace/SkillGalleryView.swift` |
| 始终在线仪表盘 | Experimental | — | `App/Views/Workspace/AlwaysOnDashboardView.swift` |
| 文件浏览器 | Experimental | — | `App/Views/Workspace/FileBrowserView.swift` |
| 统计卡片 | Experimental | — | `App/Views/Workspace/StatCard.swift` |
| 成本仪表盘 | Experimental | — | `App/Views/CostDashboardView.swift` |
| 路由设置 | Experimental | — | `App/Views/RoutingSettingsView.swift` |
| 现代化设置 | Experimental | — | `App/Views/Settings/ModernSettingsView.swift` |
| 案件工作区视图 | Experimental | — | `App/Views/CaseWorkspaceView.swift` |
| 记忆审计视图 | Experimental | — | `App/Views/MemoryAuditView.swift` |
| 工具审计视图 | Experimental | — | `App/Views/ToolAuditView.swift` |
| 案件工作区管理器 | Stable | — | `App/Managers/CaseWorkspaceManager.swift` |
| 成本仪表盘管理器 | Experimental | — | `App/Managers/CostDashboardManager.swift` |
| 记忆审计管理器 | Experimental | — | `App/Managers/MemoryAuditManager.swift` |
| 工具审计管理器 | Experimental | — | `App/Managers/ToolAuditManager.swift` |
| **设置页面** | | | |
| 提供者设置 | Stable | — | `App/Views/Settings/ProviderSettingsView.swift` |
| 技能设置 | Experimental | — | `App/Views/Settings/SkillSettingsView.swift` |
| 知识设置 | Experimental | — | `App/Views/Settings/KnowledgeSettingsView.swift` |
| MCP 设置 | Experimental | — | `App/Views/Settings/MCPSettingsView.swift` |
| 插件设置 | Experimental | — | `App/Views/Settings/PluginSettingsView.swift` |
| Tab 设置 | Stable | — | `App/Views/TabSettingsView.swift` |
| **App 状态** | | | |
| App 状态存储 | Stable | — | `App/AppStateStore.swift` |
| AXorcist 桥接 | Experimental | — | `App/AXorcistBridge.swift` |
| **测试工具** | | | |
| 分层测试运行器 | Stable | — | `scripts/run-tiered-tests.swift` |
| 集成测试 | Stable | — | `scripts/integration_test.swift` |
| 工具验证 | Stable | — | `scripts/validate-tools.swift` |
| 影响范围检测 | Experimental | — | `scripts/impact-detect.swift` |
| 插件注册同步 | Experimental | — | `scripts/sync-plugin-registry.swift` |
| **CI/CD** | | | |
| GitHub Actions CI: T0 (纯本地) | Stable | — | `.github/workflows/ci.yml` (test-t0) |
| GitHub Actions CI: T0+T1 (基线) | Stable | — | `.github/workflows/ci.yml` (test-t0t1) |
| GitHub Actions CI: 全量测试 | Stable | — | `.github/workflows/ci.yml` (test-all) |
| GitHub Actions CI: SwiftLint | Stable | — | `.github/workflows/ci.yml` (lint) |
