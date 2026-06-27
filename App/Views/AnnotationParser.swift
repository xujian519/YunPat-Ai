import Foundation

public struct TextEdit: Sendable { public let line: Int; public let oldText: String; public let newText: String; public init(line: Int, oldText: String, newText: String) { self.line = line; self.oldText = oldText; self.newText = newText } }

public struct DocumentAnnotation: Sendable { public let line: Int; public let type: AnnotationType; public let content: String; public init(line: Int, type: AnnotationType, content: String) { self.line = line; self.type = type; self.content = content } }

public enum AnnotationType: String, Sendable { case deletion; case insertion; case question; case comment }

public final class AnnotationParser {
    public func parse(_ text: String) -> (cleanText: String, annotations: [DocumentAnnotation], edits: [TextEdit]) {
        var cleanText = text; var annotations: [DocumentAnnotation] = []; var edits: [TextEdit] = []
        let lines = text.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            if let match = parsePattern("{del:", "}", in: line) {
                annotations.append(DocumentAnnotation(line: i+1, type: .deletion, content: match))
                cleanText = cleanText.replacingOccurrences(of: "{del:\(match)}", with: match)
            }
            if let match = parsePattern("{ins:", "}", in: line) {
                annotations.append(DocumentAnnotation(line: i+1, type: .insertion, content: match))
                cleanText = cleanText.replacingOccurrences(of: "{ins:\(match)}", with: match)
            }
            if line.contains("{???}") {
                let content = line.replacingOccurrences(of: "{???}", with: "").trimmingCharacters(in: .whitespaces)
                annotations.append(DocumentAnnotation(line: i+1, type: .question, content: content))
            }
        }
        return (cleanText, annotations, edits)
    }
    private func parsePattern(_ open: String, _ close: String, in line: String) -> String? {
        guard let start = line.range(of: open)?.upperBound, let end = line[start...].range(of: close)?.lowerBound else { return nil }
        return String(line[start..<end])
    }
}
