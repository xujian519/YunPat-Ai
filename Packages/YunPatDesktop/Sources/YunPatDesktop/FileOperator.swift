import Foundation

public actor FileOperator {
    private let workspaceRoot: URL

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
    }

    public func readFile(_ path: String) async throws -> Data {
        let url = resolveURL(path)
        guard isWithinWorkspace(url) else { throw FileError.pathNotAllowed(path) }
        var result = Data()
        var nsError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &nsError) { readURL in
            result = (try? Data(contentsOf: readURL)) ?? Data()
        }
        if let nsError { throw nsError }
        return result
    }

    public func writeFile(_ path: String, content: Data) async throws {
        let url = resolveURL(path)
        guard isWithinWorkspace(url) else { throw FileError.pathNotAllowed(path) }
        var nsError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &nsError) { writeURL in
            try? content.write(to: writeURL)
        }
        if let nsError { throw nsError }
    }

    public func deleteFile(_ path: String) async throws {
        let url = resolveURL(path)
        guard isWithinWorkspace(url) else { throw FileError.pathNotAllowed(path) }
        try FileManager.default.removeItem(at: url)
    }

    private func resolveURL(_ path: String) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : workspaceRoot.appendingPathComponent(path)
    }

    private func isWithinWorkspace(_ url: URL) -> Bool {
        url.path.hasPrefix(workspaceRoot.path)
    }
}

public enum FileError: Error {
    case pathNotAllowed(String)
}
