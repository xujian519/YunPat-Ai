import Foundation

public actor DocumentChangeDetector {
    private var previousContent: [URL: String] = [:]
    private let parser = AnnotationParser()

    private var watchTask: Task<Void, Never>?
    private var watchedDirectory: URL?

    public func detectChanges(in document: URL, currentContent: String) -> DocumentChangeEvent? {
        guard let previous = previousContent[document] else {
            previousContent[document] = currentContent
            return nil
        }
        guard previous != currentContent else { return nil }
        let result = parser.parse(currentContent)
        previousContent[document] = currentContent
        let questions = result.annotations.filter { $0.type == .question }.map(\.content)
        return DocumentChangeEvent(
            document: document, edits: result.edits, annotations: result.annotations, questions: questions)
    }

/// 启动文件系统监听工作目录，500ms 去抖
    public func startWatching(directory: URL, onChange: @escaping @Sendable (URL) async -> Void) {
        stopWatching()
        watchedDirectory = directory
        let dirPath: String = directory.path

        watchTask = Task {
            guard let stream = FileMonitor.stream(path: dirPath) else { return }
            var lastEventTime: ContinuousClock.Instant = .now
            let debounceInterval: Duration = .milliseconds(500)
            for await _ in stream {
                let now: ContinuousClock.Instant = .now
                guard now - lastEventTime >= debounceInterval else { continue }
                lastEventTime = now
                await onChange(directory)
            }
        }
    }

    public func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        watchedDirectory = nil
    }
}

enum FileMonitor {
    static func stream(path: String) -> AsyncStream<Void>? {
        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return nil }

        return AsyncStream { continuation in
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: [.write, .extend, .rename, .delete],
                queue: .global(qos: .utility)
            )

            source.setEventHandler {
                continuation.yield(())
            }

            source.setCancelHandler {
                close(fileDescriptor)
            }

            source.resume()

            continuation.onTermination = { _ in
                source.cancel()
            }
        }
    }
}

public struct DocumentChangeEvent: Sendable {
    public let document: URL
    public let edits: [TextEdit]
    public let annotations: [DocumentAnnotation]
    public let questions: [String]
    public init(
        document: URL, edits: [TextEdit] = [], annotations: [DocumentAnnotation] = [],
        questions: [String] = []
    ) {
        self.document = document
        self.edits = edits
        self.annotations = annotations
        self.questions = questions
    }
}
