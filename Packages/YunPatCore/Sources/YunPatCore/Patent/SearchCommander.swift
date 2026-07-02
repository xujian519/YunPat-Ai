import Foundation

/// 检索源标识
public enum SearchSource: String, Sendable {
    case cnipa
    case googlePatents
    case espacenet
    case wipo
    case semanticScholar
    case localKB  // 本地知识库
}

public struct SearchResult: Sendable {
    public let source: SearchSource
    public let patentNumber: String
    public let title: String
    public let relevanceScore: Double
    public let metadata: [String: String]
    public init(
        source: SearchSource, patentNumber: String, title: String, relevanceScore: Double = 0,
        metadata: [String: String] = [:]
    ) {
        self.source = source
        self.patentNumber = patentNumber
        self.title = title
        self.relevanceScore = relevanceScore
        self.metadata = metadata
    }
}

/// 多源检索协调器
public actor SearchCommander {
    private let wikiAdapter: WikiAdapter

    public init(wikiAdapter: WikiAdapter) { self.wikiAdapter = wikiAdapter }

    /// 按优先级从多个源检索并合并
    public func search(query: String, sources: [SearchSource] = [.localKB, .googlePatents, .cnipa]) async
        -> [SearchResult] {
        var results: [SearchResult] = []

        for source in sources {
            switch source {
            case .localKB:
                // 从宝宸知识库检索
                if let facts = try? await wikiAdapter.readModuleIndex(.patentPractice) {
                    if facts.contains(query) {
                        results.append(SearchResult(source: .localKB, patentNumber: "KB", title: query))
                    }
                }
            case .googlePatents, .cnipa, .espacenet, .wipo, .semanticScholar:
                // 外部检索 — Plan 3 中实现
                break
            }
        }

        // 合并去重
        return mergeAndRank(results)
    }

    private func mergeAndRank(_ results: [SearchResult]) -> [SearchResult] {
        var seen: Set<String> = []
        return results.sorted { $0.relevanceScore > $1.relevanceScore }.filter {
            seen.insert($0.patentNumber).inserted
        }
    }
}
