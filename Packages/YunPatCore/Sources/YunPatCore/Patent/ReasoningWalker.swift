import Foundation

// MARK: - Knowledge Graph Node

public struct ReasoningChainNode: Sendable {
    public let kgNodeId: String
    public let nodeType: String
    public let name: String
    public let relation: String
    public let excerpt: String

    public init(kgNodeId: String, nodeType: String, name: String, relation: String, excerpt: String) {
        self.kgNodeId = kgNodeId
        self.nodeType = nodeType
        self.name = name
        self.relation = relation
        self.excerpt = excerpt
    }
}

// MARK: - Legal Basis

public struct LegalBasis: Sendable {
    public let lawArticle: String?
    public let guidelineRule: String?
    public let precedentCase: String?

    public init(lawArticle: String? = nil, guidelineRule: String? = nil, precedentCase: String? = nil) {
        self.lawArticle = lawArticle
        self.guidelineRule = guidelineRule
        self.precedentCase = precedentCase
    }
}

// MARK: - Walk Chain

public struct WalkChain: Sendable {
    public let id: String
    public let factRef: String
    public let nodes: [ReasoningChainNode]
    public let legalBasis: LegalBasis
    public let confidence: Double
    public let gaps: [String]

    public init(
        id: String,
        factRef: String,
        nodes: [ReasoningChainNode],
        legalBasis: LegalBasis,
        confidence: Double,
        gaps: [String]
    ) {
        self.id = id
        self.factRef = factRef
        self.nodes = nodes
        self.legalBasis = legalBasis
        self.confidence = confidence
        self.gaps = gaps
    }
}

// MARK: - Walk Input / Output

public struct ReasoningWalkInput: Sendable {
    public let facts: [String]
    public let caseType: CaseType
    public let maxDepth: Int
    public let maxChains: Int

    public init(facts: [String], caseType: CaseType, maxDepth: Int = 3, maxChains: Int = 5) {
        self.facts = facts
        self.caseType = caseType
        self.maxDepth = maxDepth
        self.maxChains = maxChains
    }
}

public struct ReasoningWalkResult: Sendable {
    public let chains: [WalkChain]
    public let coverage: Double
    public let gaps: [String]

    public init(chains: [WalkChain], coverage: Double, gaps: [String]) {
        self.chains = chains
        self.coverage = coverage
        self.gaps = gaps
    }
}

// MARK: - Reasoning Walker

public actor ReasoningWalker {

    public init() {}

    // MARK: - Walk

    public func walk(input: ReasoningWalkInput) async -> ReasoningWalkResult {
        let chains: [WalkChain] = buildChains(
            facts: input.facts,
            maxDepth: input.maxDepth,
            maxChains: input.maxChains
        )
        let (coverage, gaps): (Double, [String]) = evaluate(chains: chains, facts: input.facts)

        return ReasoningWalkResult(chains: chains, coverage: coverage, gaps: gaps)
    }

    // MARK: - Chain Building

    // swiftlint:disable:next function_body_length
    private func buildChains(
        facts: [String],
        maxDepth: Int,
        maxChains: Int
    ) -> [WalkChain] {
        var chains: [WalkChain] = []

        for (idx, fact) in facts.prefix(maxChains).enumerated() {
            let entryNodes: [KGNode] = findEntryNodes(for: fact)
            var visited: Set<String> = Set<String>()
            var walkNodes: [ReasoningChainNode] = []

            guard let firstMatch: KGNode = entryNodes.first else {
                chains.append(
                    WalkChain(
                        id: "chain-\(idx)-no-match",
                        factRef: fact,
                        nodes: [],
                        legalBasis: LegalBasis(),
                        confidence: 0.1,
                        gaps: ["知识图谱中无匹配节点: \(fact.prefix(50))"]
                    )
                )
                continue
            }

            var queue: [(node: KGNode, depth: Int)] = [(firstMatch, 0)]

            while let (current, depth) = queue.first, depth < maxDepth {
                queue.removeFirst()

                guard !visited.contains(current.id) else { continue }
                visited.insert(current.id)

                let relation: String = depth == 0 ? "fact_to" : "next_step"
                walkNodes.append(
                    ReasoningChainNode(
                        kgNodeId: current.id,
                        nodeType: current.type,
                        name: current.name,
                        relation: relation,
                        excerpt: current.excerpt
                    )
                )

                for (targetId, rel) in current.relations {
                    if let target: KGNode = PatentLawKG.nodeMap[targetId],
                       !visited.contains(target.id) {
                        queue.append((target, depth + 1))
                    }
                    walkNodes.append(
                        ReasoningChainNode(
                            kgNodeId: "edge-\(targetId)",
                            nodeType: "relation",
                            name: rel,
                            relation: rel,
                            excerpt: "\(current.name) → \(targetId)"
                        )
                    )
                }
            }

            let gaps: [String] = detectGaps(in: walkNodes, fact: fact)
            chains.append(
                WalkChain(
                    id: "chain-\(idx)-\(UUID().uuidString.prefix(8))",
                    factRef: fact,
                    nodes: walkNodes,
                    legalBasis: extractLegalBasis(from: walkNodes),
                    confidence: computeConfidence(nodes: walkNodes, fact: fact),
                    gaps: gaps
                )
            )
        }

        return chains
    }

    // MARK: - Entry Node Matching

    private func findEntryNodes(for fact: String) -> [KGNode] {
        let lowered: String = fact.lowercased()
        var matched: [KGNode] = []
        var matchedIds: Set<String> = Set<String>()

        for (keyword, nodeIds) in PatentLawKG.keywordIndex
        where lowered.contains(keyword.lowercased()) {
            for nodeId in nodeIds where !matchedIds.contains(nodeId) {
                matchedIds.insert(nodeId)
                if let node: KGNode = PatentLawKG.nodeMap[nodeId] {
                    matched.append(node)
                }
            }
        }

        if matched.isEmpty, let defaultNode: KGNode = PatentLawKG.nodeMap["art-22-3"] {
            matched.append(defaultNode)
        }

        return matched
    }

    // MARK: - Legal Basis Extraction

    private func extractLegalBasis(from nodes: [ReasoningChainNode]) -> LegalBasis {
        var lawArticle: String?
        var guidelineRule: String?
        var precedentCase: String?

        for node in nodes {
            if node.nodeType == "legal_requirement" {
                lawArticle = node.name
            }
            if node.nodeType == "guideline" {
                guidelineRule = node.name
            }
            if node.nodeType == "legal_standard" {
                if guidelineRule == nil { guidelineRule = node.name }
            }
            if node.nodeType == "fact_pattern" {
                if precedentCase == nil { precedentCase = node.excerpt }
            }
        }

        return LegalBasis(
            lawArticle: lawArticle,
            guidelineRule: guidelineRule,
            precedentCase: precedentCase
        )
    }

    // MARK: - Evaluation

    private func evaluate(chains: [WalkChain], facts: [String]) -> (coverage: Double, gaps: [String]) {
        let coveredFacts: Set<String> = Set(chains.map(\.factRef))
        let coverage: Double = facts.isEmpty ? 0.0 : Double(coveredFacts.count) / Double(facts.count)

        var allGaps: [String] = []

        let uncovered: [String] = facts.filter { !coveredFacts.contains($0) }
        if !uncovered.isEmpty {
            allGaps.append("未覆盖的事实 (\(uncovered.count)): \(uncovered.joined(separator: "; "))")
        }

        let lowConfidence: [WalkChain] = chains.filter { $0.confidence < 0.5 }
        if !lowConfidence.isEmpty {
            allGaps.append(
                "低置信度推理链 (\(lowConfidence.count)): \(lowConfidence.map(\.id).joined(separator: ", "))"
            )
        }

        for chain in chains where !chain.gaps.isEmpty {
            allGaps.append(contentsOf: chain.gaps.map { "[\(chain.id)] \($0)" })
        }

        return (coverage, allGaps)
    }

    // MARK: - Helpers

    private func computeConfidence(nodes: [ReasoningChainNode], fact: String) -> Double {
        guard !nodes.isEmpty else { return 0.0 }

        let typeWeights: [String: Double] = [
            "legal_requirement": 1.0,
            "legal_standard": 0.9,
            "guideline": 0.8,
            "fact_pattern": 0.7,
            "relation": 0.3
        ]

        var totalWeight: Double = 0.0
        for node in nodes {
            totalWeight += typeWeights[node.nodeType] ?? 0.5
        }

        let avgWeight: Double = totalWeight / Double(nodes.count)
        let factWords: [String] = fact.lowercased().split(separator: " ").map(String.init)
        let keywordOverlap: Int = nodes.filter { node in
            factWords.contains { word in node.name.lowercased().contains(word) }
        }.count

        let overlapRatio: Double = nodes.isEmpty ? 0.0 : Double(keywordOverlap) / Double(nodes.count)
        let confidence: Double = avgWeight * (0.5 + 0.5 * overlapRatio)

        return min(confidence, 1.0)
    }

    private func detectGaps(in nodes: [ReasoningChainNode], fact: String) -> [String] {
        var gaps: [String] = []

        let legalNodes: [ReasoningChainNode] = nodes.filter {
            $0.nodeType == "legal_requirement" || $0.nodeType == "legal_standard"
        }
        if legalNodes.isEmpty {
            gaps.append("未找到法律依据节点: \(fact.prefix(50))")
        }

        let hasGuideline: Bool = nodes.contains { $0.nodeType == "guideline" }
        if !hasGuideline && nodes.count > 2 {
            gaps.append("缺少审查指南引用: \(fact.prefix(50))")
        }

        if nodes.isEmpty {
            gaps.append("空推理链 — 无知识图谱节点匹配: \(fact.prefix(50))")
        }

        return gaps
    }
}
