import Foundation

// MARK: - Structured Tool Error Codes

/// 工具层结构化错误码 — 对齐 Osaurus 模式，所有工具统一使用
public enum ToolErrorCode: String, Sendable, Codable {

    // MARK: 通用

    /// 参数缺失或格式错误
    case invalidArgs = "INVALID_ARGS"
    /// 未找到目标资源（文件/记录/数据）
    case notFound = "NOT_FOUND"
    /// 操作超时
    case timeout = "TIMEOUT"
    /// 工具内部错误
    case internalError = "INTERNAL"
    /// 未知工具名称
    case unknownTool = "UNKNOWN_TOOL"

    // MARK: 网络

    /// SSRF 防护：目标 IP 为内网/保留地址
    case ssrfBlocked = "SSRF_BLOCKED"
    /// DNS 解析失败
    case dnsError = "DNS"
    /// 网络请求失败（连接/超时/断开）
    case networkError = "NETWORK"
    /// HTTP 非 2xx 状态码
    case httpError = "HTTP_ERROR"
    /// 响应体超出配置的大小限制
    case responseTooLarge = "RESPONSE_TOO_LARGE"

    // MARK: 文件

    /// 文件读取失败（权限/不存在/IO 错误）
    case readError = "READ_ERROR"
    /// 文件写入失败（权限/磁盘满/IO 错误）
    case writeError = "WRITE_ERROR"
    /// 下载路径不安全（含 /、..、绝对路径）
    case downloadPathInvalid = "DOWNLOAD_PATH_INVALID"

    // MARK: 专利/业务

    /// 检索无匹配结果
    case noResults = "NO_RESULTS"
    /// 检索源不可用（宕机/限流/鉴权失败）
    case providerUnavailable = "PROVIDER_UNAVAILABLE"

    // MARK: 其他

    /// 内容提取失败（HTML 解析/格式转换）
    case extractionFailed = "EXTRACTION_FAILED"
    /// 权限不足（用户拒绝/未授权）
    case permissionDenied = "PERMISSION_DENIED"

    // MARK: 执行

    /// 工具执行过程中抛出异常
    case executionError = "EXECUTION_ERROR"
}
