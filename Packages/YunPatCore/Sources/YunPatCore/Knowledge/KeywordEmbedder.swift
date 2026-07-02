import Foundation

/// 开发用 mock embedder — 零依赖降级方案
///
/// 产生基于词频 hash 的伪向量（1024 维），仅用于验证 RuleEngine 管道连通。
/// 不生成真实语义向量，召回率低，仅作为 ``MLXEmbeddingProvider`` 不可用时的降级。
///
/// 算法：对每个 query term hash 到一个维度置 1.0，L2 归一化。
/// 相同文本 → 相同向量（确定性），含相同 term 的文本 → 高余弦相似度。
public struct KeywordEmbedder: EmbeddingProvider {

    public let dimension: Int = 1024
    public let modelName: String = "keyword-mock"
    public var isReady: Bool { true }

    public init() {}

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map { embedOne($0) }
    }

    private func embedOne(_ text: String) -> [Float] {
        var vec: [Float] = [Float](repeating: 0, count: dimension)

        // 按空格和 CJK 字符分词
        let terms = tokenize(text)
        for term in terms {
            // 稳定 hash（跨进程一致，不用 Swift 的随机 seed hashValue）
            let hash: Int = stableHash(term)
            let idx: Int = abs(hash) % dimension
            vec[idx] += 1.0
        }

        // L2 归一化
        let norm = sqrt(vec.map { $0 * $0 }.reduce(0, +))
        return norm > 0 ? vec.map { $0 / norm } : vec
    }

    /// 混合分词：英文按空格/标点，中文按 2-gram
    private func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        var tokens: [String] = []

        // 英文：按非字母数字分割
        let englishTerms: [String] = lowered.unicodeScalars.split { scalar in
            !scalar.properties.isAlphabetic && scalar != "_" && !("a"..."z").contains(Character(String(scalar)))
        }.map { String($0) }
        tokens.append(contentsOf: englishTerms.filter { $0.count >= 2 })

        // 中文：2-gram 滑动窗口
        let chars: [String] = lowered.compactMap { $0.isCJK ? String($0) : nil }
        if chars.count >= 2 {
            for idx in 0..<(chars.count - 1) {
                tokens.append(chars[idx] + chars[idx + 1])
            }
        }
        if chars.count >= 1 {
            tokens.append(contentsOf: chars)
        }

        return tokens
    }

    /// FNV-1a 32-bit hash — 跨进程稳定
    private func stableHash(_ str: String) -> Int {
        var hash: UInt32 = 2166136261
        for byte in str.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16777619
        }
        return Int(hash)
    }
}

private extension Character {
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
            || (0x3400...0x4DBF).contains(scalar.value)
            || (0x20000...0x2A6DF).contains(scalar.value)
    }
}
