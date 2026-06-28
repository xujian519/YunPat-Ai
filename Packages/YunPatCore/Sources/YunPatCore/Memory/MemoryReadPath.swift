import Foundation

/// MemoryReadPath — relevance-gated memory retrieval
///
/// 设计 §6：检索时做 relevance gate，不相关的记忆不注入上下文
public actor MemoryReadPath {
    public static let shared = MemoryReadPath()

    /// 相关性阈值（0-1），低于此值的记忆块被过滤
    private let relevanceThreshold: Double

    public init(relevanceThreshold: Double = 0.3) {
        self.relevanceThreshold = relevanceThreshold
    }

    /// 装配当前查询相关的记忆块
    /// - Parameters:
    ///   - query: 当前用户查询
    ///   - caseId: 案件 ID
    /// - Returns: 过滤后的记忆块，null 表示无相关记忆
    public func assemble(for query: String, caseId: String) async -> MemoryBlock? {
        let store = MemoryStore()
        guard let ctx = await store.loadCaseContext(caseId) else { return nil }

        // 相关性门控：检查每个字段与 query 的重叠度
        let techScore = relevance(query, ctx.technicalField)
        let invScore = ctx.inventionPoints.map { relevance(query, $0) }.max() ?? 0
        let refScore = ctx.keyReferences.map { relevance(query, $0) }.max() ?? 0
        let issueScore = ctx.openIssues.map { relevance(query, $0) }.max() ?? 0

        let maxScore = max(techScore, invScore, refScore, issueScore)
        guard maxScore >= relevanceThreshold else { return nil }

        // 加载 LTM 补充
        let ltm = await store.loadLongTermMemory()
        let ltmRelevant = ltm.items.filter { relevance(query, $0.content) >= relevanceThreshold }

        return MemoryBlock(
            technicalField: techScore >= 0.3 ? ctx.technicalField : nil,
            inventionPoints: ctx.inventionPoints.filter { relevance(query, $0) >= 0.3 },
            keyReferences: ctx.keyReferences.filter { relevance(query, $0) >= 0.3 },
            openIssues: ctx.openIssues.filter { relevance(query, $0) >= 0.3 },
            longTermRelevant: ltmRelevant.map(\.content)
        )
    }

    /// 简单相关性计算：query 和 target 的单词重叠率
    private func relevance(_ query: String, _ target: String) -> Double {
        guard !query.isEmpty, !target.isEmpty else { return 0 }
        let queryWords = Set(query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 })
        let targetWords = Set(target.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 })
        guard !queryWords.isEmpty else { return 0 }
        let intersection = queryWords.intersection(targetWords)
        return Double(intersection.count) / Double(max(queryWords.count, 1))
    }
}

/// 装配后的记忆块
public struct MemoryBlock: Sendable {
    public let technicalField: String?
    public let inventionPoints: [String]
    public let keyReferences: [String]
    public let openIssues: [String]
    public let longTermRelevant: [String]

    public init(technicalField: String? = nil, inventionPoints: [String] = [], keyReferences: [String] = [], openIssues: [String] = [], longTermRelevant: [String] = []) {
        self.technicalField = technicalField; self.inventionPoints = inventionPoints; self.keyReferences = keyReferences; self.openIssues = openIssues; self.longTermRelevant = longTermRelevant
    }

    /// 渲染为 LLM 可注入的文本
    public var rendered: String {
        var lines: [String] = []
        if let tf = technicalField { lines.append("技术领域: \(tf)") }
        if !inventionPoints.isEmpty { lines.append("发明点: \(inventionPoints.joined(separator: "; "))") }
        if !keyReferences.isEmpty { lines.append("关键引用: \(keyReferences.joined(separator: "; "))") }
        if !openIssues.isEmpty { lines.append("待解决问题: \(openIssues.joined(separator: "; "))") }
        guard !lines.isEmpty else { return "" }
        return "【案件记忆】\n" + lines.joined(separator: "\n")
    }
}
