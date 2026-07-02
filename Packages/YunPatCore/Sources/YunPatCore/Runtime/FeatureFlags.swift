import Foundation

// MARK: - Compile-Time Feature Gates

/// 对标 Tokio `macros/cfg.rs` 的编译时特性门控
///
/// Swift 没有 Rust Cargo feature flags 的等价物，但可以通过编译条件
/// (`#if canImport` / `#if DEBUG`) + Build Settings 预设实现类似效果。
///
/// ## 预设定义
///
/// | 预设 | 用途 |
/// |------|------|
/// | `DEBUG` | 全部启用 + 详细日志 |
/// | `RELEASE` | 全部启用 |
/// | `MINIMAL` | 仅 Core + Networking（CI 快速编译） |
///
/// ## 使用方式
///
/// ```swift
/// #if !MINIMAL_BUILD
///     let hooks = HooksService.shared
/// #endif
/// ```
///
/// 在 Xcode Build Settings → Active Compilation Conditions 中添加 `MINIMAL_BUILD`。

/// 通过 `RuntimeConfig.verboseLogging` 和编译条件联合控制日志级别
public enum FeatureFlags {
    /// 是否处于 DEBUG 模式
    public static var isDebug: Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }

    /// CI Minimal 构建（快速跳过重度模块）
    public static var isMinimalBuild: Bool {
        #if MINIMAL_BUILD
            return true
        #else
            return false
        #endif
    }

    /// 当前所有启用的 feature 名称
    public static var activeFeatures: [String] {
        var features: [String] = []
        #if DEBUG
            features.append("DEBUG")
        #endif
        #if MINIMAL_BUILD
            features.append("MINIMAL_BUILD")
        #endif
        return features
    }
}
