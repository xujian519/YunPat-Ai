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

// MARK: - Knowledge Graph (stub)

private struct KGNode: Sendable {
    let id: String
    let type: String
    let name: String
    let relations: [(targetId: String, relation: String)]
    let excerpt: String
}

// MARK: - Reasoning Walker

public actor ReasoningWalker {

    public init() {}

    // MARK: - Walk

    public func walk(input: ReasoningWalkInput) async -> ReasoningWalkResult {
        let knowledgeGraph: [String: [KGNode]] = buildStubKnowledgeGraph(caseType: input.caseType)
        let chains: [WalkChain] = buildChains(
            facts: input.facts, knowledgeGraph: knowledgeGraph,
            maxDepth: input.maxDepth, maxChains: input.maxChains
        )
        let (coverage, gaps): (Double, [String]) = evaluate(chains: chains, facts: input.facts)

        return ReasoningWalkResult(chains: chains, coverage: coverage, gaps: gaps)
    }

    // MARK: - Stub Knowledge Graph

    private func buildStubKnowledgeGraph(caseType: CaseType) -> [String: [KGNode]] {
        let topic: String = caseType.rawValue

        // Create a minimal stub graph — in production this would query a real KG store.
        let nodes: [KGNode] = [
            KGNode(
                id: "kg-\(topic)-1",
                type: "legal_requirement",
                name: "Article 22.3 Inventive Step",
                relations: [("kg-\(topic)-2", "defined_by"), ("kg-\(topic)-3", "applied_to")],
                excerpt: "An invention possesses inventive step if it is not obvious to a person skilled in the art."
            ),
            KGNode(
                id: "kg-\(topic)-2",
                type: "legal_standard",
                name: "Three-Step Test",
                relations: [("kg-\(topic)-3", "requires"), ("kg-\(topic)-4", "guides")],
                excerpt: "Determine the closest prior art, identify distinguishing features, and assess obviousness."
            ),
            KGNode(
                id: "kg-\(topic)-3",
                type: "fact_pattern",
                name: "Distinguishing Features",
                relations: [("kg-\(topic)-4", "evaluated_against")],
                excerpt: "Technical features that differentiate the claimed invention from the closest prior art."
            ),
            KGNode(
                id: "kg-\(topic)-4",
                type: "precedent",
                name: "Typical Obviousness Assessment",
                relations: [],
                excerpt:
                    "Whether the distinguishing features would have been obvious to a person skilled in the art at the filing date."  // swiftlint:disable:this line_length
            )
        ]

        // Group by topic keyword for lookup
        var graph: [String: [KGNode]] = [:]
        for node in nodes {
            let key: String = extractKeyword(from: node.name)
            graph[key, default: []].append(node)
        }
        // Also index by topic
        graph[topic] = nodes
        return graph
    }

    private func extractKeyword(from name: String) -> String {
        let normalized: String = name.lowercased()
        if normalized.contains("inventive") { return "inventive" }
        if normalized.contains("obvious") { return "obvious" }
        if normalized.contains("prior art") { return "prior_art" }
        if normalized.contains("distinguish") { return "distinguish" }
        return "general"
    }

    // MARK: - Chain Building

    // swiftlint:disable:next function_body_length
    private func buildChains(
        facts: [String],
        knowledgeGraph: [String: [KGNode]],
        maxDepth: Int,
        maxChains: Int
    ) -> [WalkChain] {
        var chains: [WalkChain] = []
        for (idx, fact) in facts.prefix(maxChains).enumerated() {
            let lowercased: String = fact.lowercased()
            var matched: [KGNode] = []
            for (keyword, nodes) in knowledgeGraph where lowercased.contains(keyword) {
                matched.append(contentsOf: nodes)
            }

            if matched.isEmpty { matched = knowledgeGraph.values.first ?? [] }
            var visited: Set<String> = Set<String>()
            var walkNodes: [ReasoningChainNode] = []
            guard let firstMatch = matched.first else { continue }
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
                    if let target = findNode(id: targetId, in: knowledgeGraph) {
                        queue.append((target, depth + 1))
                    }
                    walkNodes.append(
                        ReasoningChainNode(
                            kgNodeId: "edge-\(targetId)",
                            nodeType: "relation",
                            name: rel,
                            relation: rel,
                            excerpt: "Edge from \(current.id) to \(targetId)"
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
                    legalBasis: LegalBasis(
                        lawArticle: walkNodes.contains(where: { $0.name.contains("Article") })
                            ? "Patent Law Art. 22.3" : nil,
                        guidelineRule: walkNodes.contains(where: { $0.nodeType == "legal_standard" })
                            ? "Examination Guidelines Part II Ch. 4" : nil,
                        precedentCase: walkNodes.contains(where: { $0.nodeType == "precedent" })
                            ? "Typical inventive step assessment" : nil
                    ),
                    confidence: computeConfidence(nodes: walkNodes, fact: fact),
                    gaps: gaps
                )
            )
        }

        return chains
    }

    private func findNode(id: String, in knowledgeGraph: [String: [KGNode]]) -> KGNode? {
        for nodes in knowledgeGraph.values {
            if let node = nodes.first(where: { $0.id == id }) {
                return node
            }
        }
        return nil
    }

    // MARK: - Evaluation

    private func evaluate(chains: [WalkChain], facts: [String]) -> (coverage: Double, gaps: [String]) {
        let coveredFacts: Set<String> = Set(chains.map(\.factRef))
        let coverage: Double = facts.isEmpty ? 0.0 : Double(coveredFacts.count) / Double(facts.count)

        var allGaps: [String] = []

        // Facts without any chain
        let uncovered: [String] = facts.filter { !coveredFacts.contains($0) }
        if !uncovered.isEmpty {
            allGaps.append("Uncovered facts (\(uncovered.count)): \(uncovered.joined(separator: "; "))")
        }

        // Low-confidence chains
        let lowConfidence: [WalkChain] = chains.filter { $0.confidence < 0.5 }
        if !lowConfidence.isEmpty {
            allGaps.append(
                "Low-confidence chains (\(lowConfidence.count)): \(lowConfidence.map(\.id).joined(separator: ", "))"
            )
        }

        // Collect per-chain gaps
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
            "fact_pattern": 0.7,
            "precedent": 0.8,
            "relation": 0.3
        ]

        var totalWeight: Double = 0.0
        for node in nodes {
            totalWeight += typeWeights[node.nodeType] ?? 0.5
        }

        let avgWeight: Double = totalWeight / Double(nodes.count)

        // Penalize if the fact doesn't overlap with node names
        let keywordOverlap: Int = nodes.filter { node in
            fact.lowercased().split(separator: " ").contains { word in
                node.name.lowercased().contains(word)
            }
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
            gaps.append("No legal requirement or standard node found for fact: \(fact.prefix(50))...")
        }

        let hasPrecedent: Bool = nodes.contains { $0.nodeType == "precedent" }
        if !hasPrecedent && nodes.count > 2 {
            gaps.append("Missing precedent reference in chain for fact: \(fact.prefix(50))...")
        }

        if nodes.isEmpty {
            gaps.append("Empty chain — no KG nodes matched for fact: \(fact.prefix(50))...")
        }

        return gaps
    }
}
