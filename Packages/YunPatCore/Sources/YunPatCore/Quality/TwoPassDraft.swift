import Foundation

/// 综合诊断结果：包含禁用词检测和事实校验
public struct DiagnosisResult: Sendable {
    public let taboos: [TabooMatch]
    public let factVerification: FactVerificationResult

    /// 自动判定：error 级禁用词 → 硬失败；事实丢失 → 硬失败；否则通过
    public var verdict: RubricVerdict {
        if taboos.contains(where: { $0.rule.severity == .error }) {
            return .fail(belowMin: ["禁用词"], totalScore: 0)
        }
        if !factVerification.passed {
            return .fail(belowMin: ["事实丢失"], totalScore: 0)
        }
        return .pass
    }
}

/// 双轮草稿评估结果
public struct DraftEvaluation: Sendable {
    public let diagnosis: DiagnosisResult
    public let verdict: RubricVerdict

    public var summary: String {
        "\(verdict)\n\(diagnosis.factVerification.summary)\n禁用词: \(diagnosis.taboos.count) 处"
    }
}

/// 双轮草稿引擎 — 第一轮诊断，第二轮评估
public actor TwoPassDraft {
    private let tabooDetector: TabooDetector
    private let factEngine: FactMarkerEngine

    public init(tabooDetector: TabooDetector = TabooDetector()) {
        self.tabooDetector = tabooDetector
        self.factEngine = FactMarkerEngine()
    }

    /// 第一轮：从输入文本提取事实标记
    public func extractFacts(from text: String) async -> [FactMarker] {
        await factEngine.extract(from: text)
    }

    /// 第一轮：诊断草稿中的禁用词和事实完整性
    public func diagnose(
        draft: String, inputFacts: [FactMarker], scope: TabooScope = .claims
    ) async -> DiagnosisResult {
        let taboos = await tabooDetector.detect(in: draft, scope: scope)
        let factResult = await factEngine.verify(inputFacts: inputFacts, outputText: draft)
        return DiagnosisResult(taboos: taboos, factVerification: factResult)
    }

    /// 第二轮：综合评估并输出结构化结论
    public func evaluate(
        draft: String, inputFacts: [FactMarker], scope: TabooScope = .claims
    ) async -> DraftEvaluation {
        let d = await diagnose(draft: draft, inputFacts: inputFacts, scope: scope)
        return DraftEvaluation(diagnosis: d, verdict: d.verdict)
    }
}
