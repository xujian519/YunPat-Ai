import Foundation

public actor FactExtractor {
    public func extract(from request: UserRequest) -> StructuredFacts {
        let content = request.content
        return StructuredFacts(
            technicalField: detectTechnicalField(content),
            problem: extractProblem(content),
            inventionPoints: extractInventionPoints(content),
            missingInfo: [],
            sourceDocument: request.attachments.first
        )
    }

    private func detectTechnicalField(_ text: String) -> String {
        let fields = ["机械", "化学", "电学", "软件", "生物", "医药", "通信"]
        for f in fields { if text.contains(f) { return f } }
        return "未识别"
    }

    private func extractProblem(_ text: String) -> String {
        for p in ["问题：", "缺陷：", "不足：", "技术问题"] {
            if let range = text.range(of: p) {
                return String(text[range.upperBound...].prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text.prefix(200).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractInventionPoints(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .filter { $0.contains("特征") || $0.contains("步骤") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(10).map { $0 }
    }
}
