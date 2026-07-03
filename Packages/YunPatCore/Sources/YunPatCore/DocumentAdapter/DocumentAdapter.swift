import Foundation

// MARK: - Document Types

/// 文档解析结果 — 统一输出格式，适配器输出后可直接送入 LLM
public struct DocumentContent: Sendable, Equatable {
    public let text: String
    public let metadata: DocumentMetadata
    public let sections: [DocumentSection]

    public init(text: String, metadata: DocumentMetadata, sections: [DocumentSection] = []) {
        self.text = text
        self.metadata = metadata
        self.sections = sections
    }
}

public struct DocumentMetadata: Sendable, Equatable {
    public let fileName: String
    public let fileSize: Int
    public let pageCount: Int?
    public let author: String?
    public let createdDate: Date?
    public let modifiedDate: Date?

    public init(
        fileName: String, fileSize: Int = 0, pageCount: Int? = nil,
        author: String? = nil, createdDate: Date? = nil, modifiedDate: Date? = nil
    ) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.pageCount = pageCount
        self.author = author
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
    }
}

public struct DocumentSection: Sendable, Equatable {
    public let heading: String
    public let level: Int  // 0 = root, 1 = h1, 2 = h2, ...
    public let content: String
    public let pageNumber: Int?

    public init(heading: String, level: Int = 1, content: String = "", pageNumber: Int? = nil) {
        self.heading = heading
        self.level = level
        self.content = content
        self.pageNumber = pageNumber
    }
}

// MARK: - Adapter Protocol

/// 文档适配器协议 — 每个文件格式实现一个适配器
///
/// 职责：将文件解析为标准化的 DocumentContent，供 LLM 和工具使用。
/// 适配器不关心文件来源（本地路径 / Data / 网络），只解析内容。
public protocol DocumentAdapter: Sendable {
    /// 支持的文件扩展名（小写，不含点号）
    var supportedExtensions: Set<String> { get }

    /// 解析本地文件
    func parse(url: URL) async throws -> DocumentContent

    /// 解析二进制数据（源文件信息通过 fileName 传递以便适配器判断格式）
    func parse(data: Data, fileName: String) async throws -> DocumentContent
}

// MARK: - Default implementation

extension DocumentAdapter {
    /// 通过文件扩展名判断是否支持该文件
    public func supports(_ url: URL) -> Bool {
        guard let ext = url.pathExtension.lowercased() as String? else { return false }
        return supportedExtensions.contains(ext)
    }
}

// MARK: - Errors

public enum DocumentAdapterError: Error, Sendable, LocalizedError {
    case unsupportedFormat(String)
    case parseFailed(String)
    case fileNotFound(URL)
    case emptyContent(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "不支持的格式: \(ext)"
        case .parseFailed(let reason): return "文档解析失败: \(reason)"
        case .fileNotFound(let url): return "文件未找到: \(url.path)"
        case .emptyContent(let url): return "文档内容为空: \(url.path)"
        }
    }
}
