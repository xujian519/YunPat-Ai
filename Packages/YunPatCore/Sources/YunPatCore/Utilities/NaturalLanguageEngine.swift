import Foundation
import NaturalLanguage

/// 中文文本自然语言分析引擎
///
/// 利用 macOS NaturalLanguage 框架：
/// - 中文分词 → 增强术语提取
/// - NER 命名实体识别 → 识别技术术语/法条号/案号
/// - 语义相似度 → Skill 匹配增强
public actor NaturalLanguageEngine {
    public static let shared = NaturalLanguageEngine()

    /// 中文分词
    public func tokenize(_ text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.setLanguage(.simplifiedChinese, range: text.startIndex..<text.endIndex)

        var tokens: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            let token = String(text[range])
            if token.count > 1 { tokens.append(token) }
            return true
        }
        return tokens
    }

    /// NER 命名实体识别 — 提取法条号、案号、日期、组织名
    public func extractEntities(_ text: String) -> [Entity] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.setLanguage(.simplifiedChinese, range: text.startIndex..<text.endIndex)

        var entities: [Entity] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if let tag = tag {
                let value = String(text[range])
                entities.append(Entity(type: tag.rawValue, value: value, range: range))
            }
            return true
        }

        // 正则补充：法条号 "专利法第XX条"、案号 "CN2023..."
        let statutePattern = #"(专利法|实施细则|审查指南)第[\u4e00-\u9fa5\d]+条"#
        if let regex = try? NSRegularExpression(pattern: statutePattern) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text) {
                    entities.append(Entity(type: "STATUTE", value: String(text[range]), range: range))
                }
            }
        }

        let casePattern = #"[A-Z]{2}\d{4,}[A-Z]?"#
        if let regex = try? NSRegularExpression(pattern: casePattern) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text) {
                    entities.append(Entity(type: "CASE_ID", value: String(text[range]), range: range))
                }
            }
        }

        return entities
    }

    /// 提取关键术语（名词+动词+高信息量词）
    public func extractKeyTerms(_ text: String, topK: Int = 10) -> [String] {
        let tokens = tokenize(text)
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.setLanguage(.simplifiedChinese, range: text.startIndex..<text.endIndex)

        // 统计词频
        var freq: [String: Int] = [:]
        for token in tokens where token.count >= 2 {
            freq[token, default: 0] += 1
        }

        // 过滤名词/动词
        let contentTags: Set<String> = ["Noun", "Verb", "Adjective"]
        var scored: [(String, Double)] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if let tag = tag, contentTags.contains(tag.rawValue) {
                let token = String(text[range])
                if let count = freq[token], token.count >= 2 {
                    scored.append((token, Double(count)))
                }
            }
            return true
        }

        return scored
            .uniqued(by: \.0)
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map(\.0)
    }

    /// 文本相似度（基于词汇重叠+embedding 混合）
    public func similarity(_ a: String, _ b: String) -> Double {
        let tokensA = Set(tokenize(a.lowercased()))
        let tokensB = Set(tokenize(b.lowercased()))
        guard !tokensA.isEmpty, !tokensB.isEmpty else { return 0 }

        let intersection = tokensA.intersection(tokensB)
        let union = tokensA.union(tokensB)
        return Double(intersection.count) / Double(union.count)
    }
}

public struct Entity: Sendable {
    public let type: String
    public let value: String
    public let range: Range<String.Index>

    public init(type: String, value: String, range: Range<String.Index>) {
        self.type = type; self.value = value; self.range = range
    }
}

extension Sequence {
    func uniqued<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
