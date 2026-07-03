import Foundation

/// 桌面自动化提供者协议 — AXorcist 工具的后端接口
///
/// 设计 §5：三层能力（AXorcist / Shell / 文件系统）
/// 具体实现由 App 层注入（AppKitAXorcist），YunPatCore 仅定义接口
public protocol DesktopAutomationProvider: Sendable {
    func click(app: String, element: String) async throws
    func type(app: String, text: String, target: String) async throws
    func read(app: String, element: String) async throws -> String
    func screenshot(app: String?, region: CGRect?) async throws -> Data
    func listWindows() async throws -> [WindowInfo]
    func getProperties(app: String, element: String) async throws -> [String: String]
    func findElement(app: String, query: String) async throws -> Bool
}

/// 窗口信息 — 应用名称、窗口标题和进程 ID
public struct WindowInfo: Sendable, Codable {
    public let appName: String
    public let windowTitle: String
    public let pid: Int

    public init(appName: String, windowTitle: String, pid: Int) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.pid = pid
    }
}

/// AXorcist 工具注册器 — 管理 DesktopAutomationProvider 的注入
public enum AXorcistToolRegistry {
    private nonisolated(unsafe) static var _provider: DesktopAutomationProvider?

    public static func setProvider(_ provider: DesktopAutomationProvider) {
        _provider = provider
    }

    public static var provider: DesktopAutomationProvider? {
        _provider
    }
}
