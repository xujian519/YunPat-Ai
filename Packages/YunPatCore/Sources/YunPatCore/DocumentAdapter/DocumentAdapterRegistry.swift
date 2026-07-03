import Foundation

/// 文档适配器注册中心 — 管理所有格式的解析器
///
/// 使用方式：
/// ```swift
/// let registry = DocumentAdapterRegistry()
/// registry.register(PDFDocumentAdapter())
/// let content = try await registry.parse(url: fileURL)
/// ```
///
/// 自动选择合适的适配器（通过文件扩展名）。
/// 没有匹配适配器时抛出 `unsupportedFormat`。
public actor DocumentAdapterRegistry {
    private var adapters: [String: DocumentAdapter] = [:]

    public init() {}

    // MARK: - Registration

    /// 注册一个适配器（自动映射其所有支持的扩展名）
    public func register(_ adapter: DocumentAdapter) {
        for ext in adapter.supportedExtensions {
            adapters[ext] = adapter
        }
    }

    /// 批量注册多个适配器
    public func registerAll(_ adapters: DocumentAdapter...) {
        for adapter in adapters { register(adapter) }
    }

    /// 注销某个格式的适配器
    public func unregister(extension ext: String) {
        adapters.removeValue(forKey: ext.lowercased())
    }

    /// 获取某个扩展名对应的适配器
    public func adapter(for ext: String) -> DocumentAdapter? {
        adapters[ext.lowercased()]
    }

    /// 所有已注册的扩展名列表
    public var registeredExtensions: [String] {
        Array(adapters.keys).sorted()
    }

    // MARK: - Parsing

    /// 根据文件扩展名自动选择适配器并解析
    public func parse(url: URL) async throws -> DocumentContent {
        let ext = url.pathExtension.lowercased()
        guard let adapter = adapters[ext] else {
            throw DocumentAdapterError.unsupportedFormat(ext)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentAdapterError.fileNotFound(url)
        }
        let content: DocumentContent = try await adapter.parse(url: url)
        guard !content.text.isEmpty else {
            throw DocumentAdapterError.emptyContent(url)
        }
        return content
    }

    /// 根据文件名扩展名自动选择适配器并解析 Data
    public func parse(data: Data, fileName: String) async throws -> DocumentContent {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard let adapter = adapters[ext] else {
            throw DocumentAdapterError.unsupportedFormat(ext)
        }
        return try await adapter.parse(data: data, fileName: fileName)
    }
}
