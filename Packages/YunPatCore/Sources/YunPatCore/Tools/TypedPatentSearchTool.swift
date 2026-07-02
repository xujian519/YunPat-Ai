import Foundation

/// patent_search 强类型实现 — 多源专利检索
///
/// 通过注入的搜索闭包适配不同后端（SearchCommander / Mock / 外部 API）。
public struct PatentSearchResultItem: Codable, Sendable {
    public let patentNumber: String
    public let title: String
    public let source: String
    public let relevanceScore: Double

    public init(patentNumber: String, title: String, source: String, relevanceScore: Double) {
        self.patentNumber = patentNumber
        self.title = title
        self.source = source
        self.relevanceScore = relevanceScore
    }
}

struct TypedPatentSearchTool: TypedTool {
    let name: String = "typed_patent_search"
    let description: String = "专利检索 — 多源搜索（本地知识库、Google Patents、CNIPA）"
    var parameters: String {
        "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"检索关键词或专利号\"},"
            + "\"limit\":{\"type\":\"integer\",\"description\":\"最大返回数量\",\"default\":10}},\"required\":[\"query\"]}"
    }

    struct Args: Decodable, Sendable {
        let query: String
        let limit: Int?
    }

    private let searcher: @Sendable (String, Int) async -> [PatentSearchResultItem]

    init(searcher: @escaping @Sendable (String, Int) async -> [PatentSearchResultItem]) {
        self.searcher = searcher
    }

    func execute(input: Args, context: ToolContext) async throws -> ToolResponse {
        guard !input.query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ToolResponse.errResp(code: .invalidArgs, message: "query 不能为空")
        }
        let limit: Int = input.limit ?? 10
        let results: [PatentSearchResultItem] = await searcher(input.query, limit)

        let resultArray: [JSONValue] = results.map { item in
            .object([
                "patentNumber": .string(item.patentNumber),
                "title": .string(item.title),
                "source": .string(item.source),
                "relevanceScore": .number(item.relevanceScore)
            ])
        }

        return ToolResponse.okResp(
            data: .object([
                "query": .string(input.query),
                "results": .array(resultArray),
                "total": .number(Double(results.count))
            ]))
    }
}
