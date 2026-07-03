import Foundation

public struct TextEdit: Sendable {
    public let line: Int
    public let oldText: String
    public let newText: String
    public init(line: Int, oldText: String, newText: String) {
        self.line = line
        self.oldText = oldText
        self.newText = newText
    }
}

public struct DocumentAnnotation: Sendable {
    public let line: Int
    public let type: AnnotationType
    public let content: String
    public init(line: Int, type: AnnotationType, content: String) {
        self.line = line
        self.type = type
        self.content = content
    }
}

public enum AnnotationType: String, Sendable {
    case deletion
    case insertion
    case question
    case comment
}

public struct ParsedAnnotationResult: Sendable {
    public let cleanText: String
    public let annotations: [DocumentAnnotation]
    public let edits: [TextEdit]
    public init(cleanText: String, annotations: [DocumentAnnotation], edits: [TextEdit]) {
        self.cleanText = cleanText
        self.annotations = annotations
        self.edits = edits
    }
}

public final class AnnotationParser {

    public init() {}

    public func parse(_ text: String) -> ParsedAnnotationResult {
        var cleanLines: [String] = []
        var annotations: [DocumentAnnotation] = []
        var edits: [TextEdit] = []
        let lines: [String] = text.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let lineNumber: Int = index + 1
            var cleanLine: String = line

            // {del:text} — 删除标注
            if let match: String = parsePattern("{del:", "}", in: line) {
                annotations.append(DocumentAnnotation(line: lineNumber, type: .deletion, content: match))
                let originalLine: String = line
                cleanLine = cleanLine.replacingOccurrences(of: "{del:\(match)}", with: match)
                edits.append(TextEdit(line: lineNumber, oldText: originalLine, newText: cleanLine))
            }

            // {ins:text} — 插入标注
            if let match: String = parsePattern("{ins:", "}", in: line) {
                annotations.append(DocumentAnnotation(line: lineNumber, type: .insertion, content: match))
                let beforeInsertion: String = cleanLine
                let insertionText: String = match
                cleanLine = cleanLine.replacingOccurrences(of: "{ins:\(match)}", with: insertionText)
                edits.append(TextEdit(line: lineNumber, oldText: beforeInsertion, newText: cleanLine))
            }

            // {???} — 疑问标注
            if line.contains("{???}") {
                let questionContent: String = line
                    .replacingOccurrences(of: "{???}", with: "")
                    .trimmingCharacters(in: .whitespaces)
                annotations.append(
                    DocumentAnnotation(line: lineNumber, type: .question, content: questionContent)
                )
                cleanLine = cleanLine.replacingOccurrences(of: "{???}", with: "")
            }

            // 💬 — 评论标注
            if line.contains("💬") {
                let parts: [String] = line.components(separatedBy: "💬")
                if parts.count > 1 {
                    let comment: String = parts.last?.trimmingCharacters(in: .whitespaces) ?? ""
                    annotations.append(
                        DocumentAnnotation(line: lineNumber, type: .comment, content: comment)
                    )
                }
                cleanLine = cleanLine.components(separatedBy: "💬").first ?? cleanLine
                cleanLine = cleanLine.trimmingCharacters(in: .whitespaces)
            }

            cleanLines.append(cleanLine)
        }

        let cleanText: String = cleanLines.joined(separator: "\n")
        return ParsedAnnotationResult(
            cleanText: cleanText,
            annotations: annotations,
            edits: edits
        )
    }

    private func parsePattern(_ open: String, _ close: String, in line: String) -> String? {
        guard let start: String.Index = line.range(of: open)?.upperBound,
              let end: String.Index = line[start...].range(of: close)?.lowerBound
        else { return nil }
        return String(line[start..<end])
    }
}
