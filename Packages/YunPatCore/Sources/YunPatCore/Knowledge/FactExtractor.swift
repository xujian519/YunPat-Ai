import Foundation
import NaturalLanguage

public actor FactExtractor {
    private let engine: NaturalLanguageEngine = .shared

    public func extract(from request: UserRequest) async -> StructuredFacts {
        let content: String = request.content
        let entities: [Entity] = await engine.extractEntities(content)
        let statuteRefs = entities.filter { $0.type == "STATUTE" }.map(\.value)
        let caseRefs = entities.filter { $0.type == "CASE_ID" }.map(\.value)

        return StructuredFacts(
            technicalField: await detectTechnicalField(content),
            problem: await extractProblem(content),
            inventionPoints: await extractInventionPoints(content) + statuteRefs,
            missingInfo: [],
            sourceDocument: request.attachments.first,
            caseReferences: caseRefs
        )
    }

    private func detectTechnicalField(_ text: String) async -> String {
        let fields: [String] = ["机械", "化学", "电学", "软件", "生物", "医药", "通信"]
        for flag in fields where text.contains(flag) { return flag }
        let terms: [String] = await engine.extractKeyTerms(text, topK: 5)
        let fieldKeywords: [String: String] = [
            "齿轮": "机械", "轴承": "机械", "弹簧": "机械",
            "化合物": "化学", "反应": "化学", "分子": "化学",
            "电路": "电学", "信号": "电学", "电压": "电学",
            "算法": "软件", "数据库": "软件", "接口": "软件",
            "细胞": "生物", "基因": "生物", "蛋白": "生物"
        ]
        for term in terms {
            if let field = fieldKeywords[term] { return field }
        }
        return "未识别"
    }

    private func extractProblem(_ text: String) async -> String {
        for path in ["问题：", "缺陷：", "不足：", "技术问题"] {
            if let range = text.range(of: path) {
                return String(text[range.upperBound...].prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let tokens: [String] = await engine.tokenize(text)
        return tokens.prefix(15).joined()
    }

    private func extractInventionPoints(_ text: String) async -> [String] {
        let keyTerms: [String] = await engine.extractKeyTerms(text, topK: 8)
        let structuralLines = text.components(separatedBy: .newlines)
            .filter { $0.contains("特征") || $0.contains("步骤") || $0.contains("包括") || $0.contains("包含") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(10).map { $0 }

        return Array((structuralLines + keyTerms).prefix(10))
    }
}
