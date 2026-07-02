import Foundation

// MARK: - PathSecurity

/// 路径安全工具 — 提供 resolvePath / validatePath / safeResolve 三步路径防护
///
/// 提供两类防护：
/// 1. `resolvePath` — 相对路径 → 工作目录下的绝对路径
/// 2. `validatePath` — 防止目录遍历攻击
public enum PathSecurity: Sendable {

    /// 解析路径：相对路径拼接 `base`，绝对路径直接返回
    /// - Parameters:
    ///   - path: 用户传入的路径（相对或绝对）
    ///   - base: 工作目录
    /// - Returns: 标准化后的绝对路径
    public static func resolvePath(_ path: String, relativeTo base: String) -> String {
        guard !path.hasPrefix("/") else { return (path as NSString).standardizingPath }
        return ((base as NSString).appendingPathComponent(path) as NSString).standardizingPath
    }

    /// 验证路径是否在允许的基目录内（防目录遍历）
    /// - Parameters:
    ///   - absolutePath: 已解析的绝对路径
    ///   - allowedBase: 允许的基目录
    /// - Returns: 安全则 true
    ///
    /// ```swift
    /// PathSecurity.validatePath("/Users/me/project/../../etc/passwd", allowedBase: "/Users/me/project")
    /// // → false
    /// ```
    public static func validatePath(_ absolutePath: String, allowedBase: String) -> Bool {
        let resolved: String = (absolutePath as NSString).standardizingPath
        let base: String = (allowedBase as NSString).standardizingPath
        let baseWithSlash: String = base.hasSuffix("/") ? base : "\(base)/"
        return resolved == base || resolved.hasPrefix(baseWithSlash)
    }

    /// 便捷方法：resolve + validate 一步完成
    /// - Returns: 安全通过则返回解析后的绝对路径，否则 nil
    public static func safeResolve(_ path: String, relativeTo base: String) -> String? {
        let resolved = resolvePath(path, relativeTo: base)
        guard validatePath(resolved, allowedBase: base) else { return nil }
        return resolved
    }
}
