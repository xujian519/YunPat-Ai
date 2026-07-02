import Foundation

/// knowledge_search 强类型实现 — 知识库语义检索
///
/// 通过注入的搜索闭包适配不同后端（VectorSearch / 关键词 / 外部索引）。
public struct KnowledgeSearchResultItem: Codable, Sendable {
    public let content: String
    public let score: Double
    public let source: String?

    public init(content: String, score: Double, source: String? = nil) {
        self.content = content
        self.score = score
        self.source = source
    }
}

struct TypedKnowledgeSearchTool: TypedTool {
    let name: String = "typed_knowledge_search"
    let description: String = "知识库语义检索 — 搜索本地知识库中与查询相关的文档片段"
    var parameters: String {
        "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"搜索查询\"},"
            + "\"limit\":{\"type\":\"integer\",\"description\":\"最大返回数量\",\"default\":5}},\"required\":[\"query\"]}"
    }

    struct Args: Decodable, Sendable {
        let query: String
        let limit: Int?
    }

    private let searcher: @Sendable (String, Int) async -> [KnowledgeSearchResultItem]

    init(searcher: @escaping @Sendable (String, Int) async -> [KnowledgeSearchResultItem]) {
        self.searcher = searcher
    }

    func execute(input: Args, context: ToolContext) async throws -> ToolResponse {
        guard !input.query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ToolResponse.errResp(code: .invalidArgs, message: "query 不能为空")
        }
        let limit: Int = input.limit ?? 5
        let results: [KnowledgeSearchResultItem] = await searcher(input.query, limit)

        let resultArray: [JSONValue] = results.map { item in
            var obj: [String: JSONValue] = [
                "content": .string(item.content),
                "score": .number(item.score)
            ]
            if let src = item.source { obj["source"] = .string(src) }
            return .object(obj)
        }

        return ToolResponse.okResp(
            data: .object([
                "query": .string(input.query),
                "results": .array(resultArray),
                "total": .number(Double(results.count))
            ]))
    }
}
