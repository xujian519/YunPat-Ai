import AppKit
import ScreenCaptureKit
import YunPatCore
import YunPatDesktop

/// AppKitAXorcistBridge — 桥接 YunPatDesktop 的 AXorcist 到 YunPatCore 的 DesktopAutomationProvider
///
/// 在 App 启动时调用 AXorcistBridge.register() 注入
///
/// **并发安全**: actor 隔离确保 _lastRoute 写入只在 actor 方法内发生；
/// lastRouteDescription 使用 nonisolated(unsafe) 满足 DesktopAutomationProvider 协议要求
/// （同步只读属性），写入仅在与 _lastRoute 相同线程安全的 actor 边界内完成。
actor AXorcistBridge: DesktopAutomationProvider {
    private let axorcist: AppKitAXorcist = AppKitAXorcist()
    private nonisolated(unsafe) var _lastRoute: InputRoute = .accessibility

    static func register() {
        AXorcistToolRegistry.setProvider(AXorcistBridge())
    }

    nonisolated var lastRouteDescription: String { _lastRoute.rawValue }

    func click(app: String, element: String) async throws {
        try await axorcist.click(app: app, element: element)
        _lastRoute = await axorcist.lastRoute
    }

    func type(app: String, text: String, target: String) async throws {
        try await axorcist.type(app: app, text: text, target: target)
        _lastRoute = await axorcist.lastRoute
    }

    func read(app: String, element: String) async throws -> String {
        try await axorcist.read(app: app, element: element)
    }

    func screenshot(app: String?, region: CGRect?) async throws -> Data {
        try await axorcist.screenshot(app: app, region: region)
    }

    func listWindows() async throws -> [WindowInfo] {
        let scContent: SCShareableContent = try await SCShareableContent.current
        return scContent.windows.filter { $0.isOnScreen }.map { window in
            WindowInfo(
                appName: window.owningApplication?.applicationName ?? "Unknown",
                windowTitle: window.title ?? "",
                pid: Int(window.owningApplication?.processID ?? 0)
            )
        }
    }

    func getProperties(app: String, element: String) async throws -> [String: String] {
        guard let pid = pidOfApp(app) else {
            throw AXorcistBridgeError.appNotFound(app)
        }
        let axApp = AXUIElementCreateApplication(pid)
        guard let axEl = findElement(in: axApp, label: element) else {
            throw AXorcistBridgeError.elementNotFound(app: app, element: element)
        }
        var props: [String: String] = [:]
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
                     kAXRoleAttribute, kAXSubroleAttribute, kAXHelpAttribute] {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(axEl, attr as CFString, &value)
            if result == .success, let str = value as? String {
                props[attr as String] = str
            }
        }
        return props
    }

    func findElement(app: String, query: String) async throws -> Bool {
        guard let pid = pidOfApp(app) else {
            throw AXorcistBridgeError.appNotFound(app)
        }
        let axApp = AXUIElementCreateApplication(pid)
        return findElement(in: axApp, label: query) != nil
    }

    // MARK: - AX Tree Helpers (only for getProperties/findElement)

    private func findElement(in axApp: AXUIElement, label: String) -> AXUIElement? {
        searchAXTree(axApp, target: label, depth: 0, maxDepth: 8)
    }

    private func searchAXTree(_ element: AXUIElement, target: String, depth: Int, maxDepth: Int) -> AXUIElement? {
        if depth > maxDepth { return nil }
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
            if result == .success, let str = value as? String {
                if str.localizedCaseInsensitiveContains(target) { return element }
            }
        }
        var children: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        guard result == .success, let childArray = children as? [AXUIElement] else { return nil }
        for child in childArray {
            if let found = searchAXTree(child, target: target, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
        return nil
    }

    private func pidOfApp(_ name: String) -> pid_t? {
        NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.localizedCaseInsensitiveContains(name) == true
        }?.processIdentifier
    }
}

enum AXorcistBridgeError: Error, LocalizedError {
    case appNotFound(String)
    case elementNotFound(app: String, element: String)
    case readFailed(String)
    case screenshotFailed

    var errorDescription: String? {
        switch self {
        case .appNotFound(let app): "未找到运行中的应用: \(app)"
        case .elementNotFound(let app, let element): "未找到 \(app) 中的元素: \(element)"
        case .readFailed(let element): "读取元素失败: \(element)"
        case .screenshotFailed: "截图失败"
        }
    }
}
