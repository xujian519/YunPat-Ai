import AppKit
import Foundation

/// AppleScript / OSA 脚本桥接层
///
/// 设计 §1 macOS 独占特性：Spotlight、Shortcuts、AppleScript 集成。
/// 提供脚本执行、Shortcuts 调用、Spotlight 搜索能力。
public final class AppleScriptBridge: @unchecked Sendable {

    // MARK: - AppleScript Execution

    /// 执行 AppleScript 代码，返回结果文本
    public func execute(_ script: String) throws -> String {
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw ScriptBridgeError.compileFailed(script.prefix(80).description)
        }
        let result = appleScript.executeAndReturnError(&error)
        if let error = error {
            let code: Int = error[NSAppleScript.errorNumber] as? Int ?? -1
            let message: String = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
            throw ScriptBridgeError.executionFailed(code: code, message: message)
        }
        return result.stringValue ?? ""
    }

    /// 执行 AppleScript 文件
    public func execute(file url: URL) throws -> String {
        let source = try String(contentsOf: url, encoding: .utf8)
        return try execute(source)
    }

    // MARK: - Shortcuts Integration

    /// 运行指定的 Shortcut（按名称）
    @available(macOS 12.0, *)
    public func runShortcut(named name: String, input: String? = nil) async throws -> String {
        let inputPart: String = input.map { "with input \"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" } ?? ""
        let script: String
        if !inputPart.isEmpty {
            script = "tell application \"Shortcuts\" to run shortcut \"\(name)\" \(inputPart)"
        } else {
            script = "tell application \"Shortcuts\" to run shortcut \"\(name)\""
        }
        return try execute(script)
    }

    /// 列出可用的 Shortcuts
    @available(macOS 12.0, *)
    public func listShortcuts() throws -> [String] {
        let script: String = """
            tell application "Shortcuts"
                set shortcutNames to name of every shortcut
                return shortcutNames as text
            end tell
            """
        let result = try execute(script)
        return result.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Spotlight Search

    /// 通过 mdfind 命令行执行 Spotlight 搜索
    public func spotlightSearch(_ query: String, limit: Int = 20) throws -> [SpotlightResult] {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-name", query, "-count", String(limit)]

        let pipe: Pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let output: String = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let paths: [String] = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

        return paths.prefix(limit).compactMap { path in
            let url: URL = URL(fileURLWithPath: path)
            var isDir: ObjCBool = ObjCBool(false)
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
            return SpotlightResult(
                path: path,
                name: url.lastPathComponent,
                isDirectory: isDir.boolValue,
                size: size
            )
        }
    }

    /// 通过 mdls 获取文件元数据
    public func spotlightMetadata(for path: String) throws -> [String: String] {
        let process: Process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = ["-raw", path]

        let pipe: Pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let output: String = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var metadata: [String: String] = [String: String]()
        for line in output.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: " = ")
            if parts.count == 2 {
                metadata[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1]
            }
        }
        return metadata
    }

    // MARK: - macOS Application Control

    /// 激活指定应用
    public func activateApp(named name: String) throws {
        let script: String = "tell application \"\(name)\" to activate"
        _ = try execute(script)
    }

    /// 打开文件/URL
    public func open(_ url: URL) throws {
        NSWorkspace.shared.open(url)
    }

    /// 通过 Finder 显示文件
    public func revealInFinder(_ path: String) throws {
        let url: URL = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 获取当前活跃应用名称
    public func frontmostApp() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}

// MARK: - Types

public struct SpotlightResult: Sendable {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let size: UInt64

    public init(path: String, name: String, isDirectory: Bool, size: UInt64) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
    }
}

public enum ScriptBridgeError: Error, LocalizedError {
    case compileFailed(String)
    case executionFailed(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .compileFailed(let msg): return "AppleScript 编译失败: \(msg)"
        case .executionFailed(let code, let msg): return "AppleScript 错误 (\(code)): \(msg)"
        }
    }
}
