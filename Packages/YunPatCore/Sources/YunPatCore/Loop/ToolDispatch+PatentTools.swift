import Foundation

// MARK: - Patent Tools 注册 & 处理

extension ToolDispatch {

    // MARK: - Injection Points

    /// 专利检索注入点 — App 启动时配置
    private final class PatentToolHandlers: @unchecked Sendable {
        static let shared: PatentToolHandlers = PatentToolHandlers()
        private let lock: NSLock = NSLock()

        private var _patentSearcher: (@Sendable (String, Int) async -> [PatentSearchResultItem])?
        private var _knowledgeSearcher: (@Sendable (String, Int) async -> [KnowledgeSearchResultItem])?
        private var _legalStatusQuerier: (@Sendable (String) async -> LegalStatusResult?)?

        var patentSearcher: (@Sendable (String, Int) async -> [PatentSearchResultItem])? {
            get { lock.withLock { _patentSearcher } }
            set { lock.withLock { _patentSearcher = newValue } }
        }
        var knowledgeSearcher: (@Sendable (String, Int) async -> [KnowledgeSearchResultItem])? {
            get { lock.withLock { _knowledgeSearcher } }
            set { lock.withLock { _knowledgeSearcher = newValue } }
        }
        var legalStatusQuerier: (@Sendable (String) async -> LegalStatusResult?)? {
            get { lock.withLock { _legalStatusQuerier } }
            set { lock.withLock { _legalStatusQuerier = newValue } }
        }

        private init() {}
    }

    /// 配置专利检索后端
    public func configurePatentSearch(
        _ searcher: @Sendable @escaping (String, Int) async -> [PatentSearchResultItem]
    ) {
        PatentToolHandlers.shared.patentSearcher = searcher
    }

    /// 配置知识库检索后端
    public func configureKnowledgeSearch(
        _ searcher: @Sendable @escaping (String, Int) async -> [KnowledgeSearchResultItem]
    ) {
        PatentToolHandlers.shared.knowledgeSearcher = searcher
    }

    /// 配置法律状态查询后端
    public func configureLegalStatus(
        _ querier: @Sendable @escaping (String) async -> LegalStatusResult?
    ) {
        PatentToolHandlers.shared.legalStatusQuerier = querier
    }

    // MARK: - Registration

    func registerPatentTools() {
        handlers["patent_search"] = { name, input, context in
            await Self.handlePatentSearch(name: name, input: input, ctx: context)
        }
        toolSpecs["patent_search"] = ToolSpec(
            name: "patent_search",
            description: "在 Google Patents / CNIPA 检索专利文献。传入布尔检索式或关键词。"
        )
        handlers["legal_status_query"] = { name, input, context in
            await Self.handleLegalStatusQuery(name: name, input: input, ctx: context)
        }
        toolSpecs["legal_status_query"] = ToolSpec(
            name: "legal_status_query",
            description: "查询专利的法律状态。传入专利公开号。"
        )
        handlers["knowledge_search"] = { name, input, context in
            await Self.handleKnowledgeSearch(name: name, input: input, ctx: context)
        }
        toolSpecs["knowledge_search"] = ToolSpec(
            name: "knowledge_search",
            description: "在知识库中检索专利法规、审查指南和判例。"
        )
        handlers["capabilities_discover"] = { name, input, context in
            await Self.handleCapabilitiesDiscover(name: name, input: input, ctx: context)
        }
        toolSpecs["capabilities_discover"] = ToolSpec(
            name: "capabilities_discover",
            description: "搜索已启用的能力。传入搜索关键词。返回匹配的能力列表。"
        )
        handlers["capabilities_load"] = { name, input, context in
            await Self.handleCapabilitiesLoad(name: name, input: input, ctx: context)
        }
        toolSpecs["capabilities_load"] = ToolSpec(
            name: "capabilities_load",
            description: "加载一个能力到当前会话。传入 capabilities_discover 返回的能力名称。"
        )
    }

    // MARK: - Patent Search

    private struct PatentSearchRow {
        let patentNumber: String
        let title: String
        let source: String
        let score: Double
    }

    private static func patentSearchResponse(
        query: String,
        results: [PatentSearchRow],
        count: Int
    ) -> ToolHandlerResult {
        let resultArray: [JSONValue] = results.map {
            JSONValue.object([
                "patentNumber": .string($0.patentNumber),
                "title": .string($0.title),
                "source": .string($0.source),
                "relevanceScore": .number($0.score)
            ])
        }
        return .handled(
            ToolResponse.okResp(
                data: .object([
                    "query": .string(query),
                    "results": .array(resultArray),
                    "total": .number(Double(count))
                ])
            ).jsonString()
        )
    }

    private static func handlePatentSearch(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let query: String = input["query"]?.stringValue ?? ""
        guard !query.isEmpty else {
            return .handled(
                ToolResponse.errResp(
                    code: .invalidArgs, message: "query 参数不能为空"
                ).jsonString()
            )
        }
        let limit: Int = input["limit"]?.intValue ?? 10

        // 优先路径：注入式 searcher
        if let searcher = PatentToolHandlers.shared.patentSearcher {
            let results: [PatentSearchResultItem] = await searcher(query, limit)
            let mapped = results.map {
                PatentSearchRow(
                    patentNumber: $0.patentNumber, title: $0.title,
                    source: $0.source, score: $0.relevanceScore
                )
            }
            return patentSearchResponse(query: query, results: mapped, count: results.count)
        }

        // 降级路径 1：SearchCommander
        if let commander = ToolDispatch.shared.searchCommander {
            let results: [SearchResult] = await commander.search(query: query)
            let limited: [SearchResult] = Array(results.prefix(limit))
            guard !limited.isEmpty else {
                return .handled(
                    ToolResponse.errResp(
                        code: .notFound,
                        message: "未找到与「\(query)」相关的结果。"
                    ).jsonString()
                )
            }
            let mapped = limited.map {
                PatentSearchRow(
                    patentNumber: $0.patentNumber, title: $0.title,
                    source: $0.source.rawValue, score: $0.relevanceScore
                )
            }
            return patentSearchResponse(query: query, results: mapped, count: limited.count)
        }

        // 降级路径 2：未配置
        return .handled(
            ToolResponse.errResp(
                    code: .providerUnavailable,
                    message: "专利检索后端未配置。请先调用 configurePatentSearch() 注入检索实现。"
            ).jsonString()
        )
    }

    // MARK: - Legal Status Query

    private static func handleLegalStatusQuery(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let patentNumber: String = input["patent_number"]?.stringValue ?? ""
        guard !patentNumber.isEmpty else {
            return .handled(
                ToolResponse.errResp(
                    code: .invalidArgs, message: "patent_number 参数不能为空"
                ).jsonString()
            )
        }

        // 优先路径：注入式 querier
        if let querier = PatentToolHandlers.shared.legalStatusQuerier {
            let result: LegalStatusResult? = await querier(patentNumber)
            if let result {
                return .handled(
                    ToolResponse.okResp(
                        data: .object([
                            "patentNumber": .string(result.patentNumber),
                            "legalStatus": .string(result.legalStatus),
                            "statusDetail": .string(result.statusDetail)
                        ])
                    ).jsonString()
                )
            }
            return .handled(
                ToolResponse.errResp(
                    code: .notFound,
                    message: "未找到专利 '\(patentNumber)' 的法律状态信息"
                ).jsonString()
            )
        }

        // 降级：未配置
        return .handled(
            ToolResponse.errResp(
                    code: .providerUnavailable,
                    message: "法律状态查询后端未配置。请先调用 configureLegalStatus() 注入查询实现。"
            ).jsonString()
        )
    }

    // MARK: - Knowledge Search

    private static func handleKnowledgeSearch(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let query: String = input["query"]?.stringValue ?? ""
        guard !query.isEmpty else {
            return .handled(
                ToolResponse.errResp(
                    code: .invalidArgs, message: "query 参数不能为空"
                ).jsonString()
            )
        }
        let limit: Int = input["limit"]?.intValue ?? 5

        // 优先路径：注入式 searcher（语义检索）
        if let searcher = PatentToolHandlers.shared.knowledgeSearcher {
            let results: [KnowledgeSearchResultItem] = await searcher(query, limit)
            let resultArray: [JSONValue] = results.map { item in
                var obj: [String: JSONValue] = [
                    "content": .string(item.content),
                    "score": .number(item.score)
                ]
                if let src: String = item.source {
                    obj["source"] = .string(src)
                }
                return JSONValue.object(obj)
            }
            return .handled(
                ToolResponse.okResp(
                    data: .object([
                        "query": .string(query),
                        "results": .array(resultArray),
                        "total": .number(Double(results.count))
                    ])
                ).jsonString()
            )
        }

        // 降级路径：SearchCommander localKB
        if let commander = ToolDispatch.shared.searchCommander {
            let results: [SearchResult] = await commander.search(
                query: query, sources: [.localKB]
            )
            if !results.isEmpty {
                let resultArray: [JSONValue] = results.prefix(limit).map { item in
                    JSONValue.object([
                        "content": .string(item.title),
                        "score": .number(item.relevanceScore),
                        "source": .string(item.source.rawValue)
                    ])
                }
                return .handled(
                    ToolResponse.okResp(
                        data: .object([
                            "query": .string(query),
                            "results": .array(resultArray),
                            "total": .number(Double(results.count))
                        ])
                    ).jsonString()
                )
            }
        }

        // 降级路径：未配置
        return .handled(
            ToolResponse.errResp(
                    code: .providerUnavailable,
                    message: "知识库检索后端未配置。请先调用 configureKnowledgeSearch() 注入检索实现。"
            ).jsonString()
        )
    }

    // MARK: - Capability Tools

    private static func handleCapabilitiesDiscover(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let query: String = (input["query"]?.stringValue ?? "").lowercased()
        let registry: CapabilityRegistry = CapabilityRegistry()
        var matches: [String] = []

        for cap: CapabilityDefinition in await registry.listCapabilities() {
            if query.isEmpty || cap.name.lowercased().contains(query)
                || cap.displayName.lowercased().contains(query)
                || cap.description.lowercased().contains(query) {
                let net: String = cap.metadata.requiresNetwork ? " 🌐" : ""
                matches.append("- \(cap.displayName) (`\(cap.name)`)\(net) — \(cap.description)")
            }
        }

        if matches.isEmpty {
            return .handled("没有找到匹配的能力。尝试更宽的关键词。")
        }
        return .handled("【匹配的能力】\n" + matches.joined(separator: "\n"))
    }

    private static func handleCapabilitiesLoad(
        name: String, input: [String: JSONValue], ctx: ToolContext
    ) async -> ToolHandlerResult {
        let capName: String = input["name"]?.stringValue ?? ""
        guard !capName.isEmpty else { return .handled("Error: name field required") }

        let registry: CapabilityRegistry = CapabilityRegistry()
        guard let cap: CapabilityDefinition = await registry.listCapabilities()
            .first(where: { $0.name == capName })
        else {
            return .handled("Error: 未找到能力 '\(capName)'。先使用 capabilities_discover 查找可用能力。")
        }

        await CapabilityLoadBuffer.shared.recordLoad(capName)

        let details: String = """
            已加载能力: \(cap.displayName) (\(cap.name))
            描述: \(cap.description)
            来源: \(cap.source.rawValue)
            权限: \(cap.permission.rawValue)
            🌐 需要网络: \(cap.metadata.requiresNetwork)
            典型场景: \(cap.metadata.typicalUseCases.joined(separator: ", "))
            """
        return .handled(details)
    }
}

// MARK: - Legal Status Result Type

/// 法律状态查询结果
public struct LegalStatusResult: Sendable {
    public let patentNumber: String
    public let legalStatus: String
    public let statusDetail: String

    public init(patentNumber: String, legalStatus: String, statusDetail: String = "") {
        self.patentNumber = patentNumber
        self.legalStatus = legalStatus
        self.statusDetail = statusDetail
    }
}
