import Foundation

public struct FactMarker: Sendable, Codable {
    public let id: UUID
    public let fact: String
    public let source: String
    public let verified: Bool

    public init(id: UUID = UUID(), fact: String, source: String, verified: Bool = false) {
        self.id = id
        self.fact = fact
        self.source = source
        self.verified = verified
    }
}

public struct FactVerificationResult: Sendable {
    public let passed: Bool
    public let preservedCount: Int
    public let lostFacts: [FactMarker]
    public let addedFacts: [FactMarker]

    public var summary: String {
        passed
            ? "✅ 全部 \(preservedCount) 个事实已保留"
            : "❌ 丢失 \(lostFacts.count) 个事实: \(lostFacts.map(\.fact).joined(separator: "; "))"
    }
}

public actor FactMarkerEngine {
    public init() {}

    public func extract(from text: String) -> [FactMarker] {
        let pattern = #"\[FACT:\s*([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return FactMarker(fact: String(text[range]), source: "extracted")
        }
    }

    public func verify(inputFacts: [FactMarker], outputText: String) -> FactVerificationResult {
        let markedFacts = extract(from: outputText)
        let markedIDs = Set(markedFacts.map(\.fact))
        let inputIDs = Set(inputFacts.map(\.fact))

        // Preserved if found in [FACT: ...] markers OR plain-text contained in output
        let preserved = inputIDs.filter { fact in
            markedIDs.contains(fact) || outputText.contains(fact)
        }
        let lost = inputIDs.subtracting(preserved)
        let addedIDs = markedIDs.subtracting(inputIDs)
        return FactVerificationResult(
            passed: lost.isEmpty,
            preservedCount: preserved.count,
            lostFacts: inputFacts.filter { lost.contains($0.fact) },
            addedFacts: markedFacts.filter { addedIDs.contains($0.fact) }
        )
    }

    public func mark(_ text: String, fact: String, source: String) -> String {
        text.replacingOccurrences(
            of: fact, with: "[FACT: \(source)]\(fact)[/FACT]")
    }
}
