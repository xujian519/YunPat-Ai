import Foundation

public actor DocumentChangeDetector {
    private var previousContent: [URL: String] = [:]
    private let parser = AnnotationParser()

    public func detectChanges(in document: URL, currentContent: String) -> DocumentChangeEvent? {
        guard let previous = previousContent[document] else { previousContent[document] = currentContent; return nil }
        guard previous != currentContent else { return nil }
        let result = parser.parse(currentContent)
        previousContent[document] = currentContent
        let questions = result.annotations.filter { $0.type == .question }.map(\.content)
        return DocumentChangeEvent(document: document, edits: result.edits, annotations: result.annotations, questions: questions)
    }
}

public struct DocumentChangeEvent: Sendable {
    public let document: URL; public let edits: [TextEdit]; public let annotations: [DocumentAnnotation]; public let questions: [String]
    public init(document: URL, edits: [TextEdit] = [], annotations: [DocumentAnnotation] = [], questions: [String] = []) { self.document = document; self.edits = edits; self.annotations = annotations; self.questions = questions }
}
