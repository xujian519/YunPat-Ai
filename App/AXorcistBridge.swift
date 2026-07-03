import AppKit
import ScreenCaptureKit
import YunPatCore

/// AppKitAXorcistBridge — 桥接 YunPatDesktop 的 AXorcist 到 YunPatCore 的 DesktopAutomationProvider
///
/// 在 App 启动时调用 AXorcistBridge.register() 注入
final class AXorcistBridge: DesktopAutomationProvider, @unchecked Sendable {

    static func register() {
        AXorcistToolRegistry.setProvider(AXorcistBridge())
    }

    func click(app: String, element: String) async throws {
        guard let pid = pidOfApp(app) else {
            throw AXorcistBridgeError.appNotFound(app)
        }
        let axApp = AXUIElementCreateApplication(pid)
        guard let axEl = findElement(in: axApp, label: element) else {
            throw AXorcistBridgeError.elementNotFound(app: app, element: element)
        }
        AXUIElementPerformAction(axEl, kAXPressAction as CFString)
    }

    func type(app: String, text: String, target: String) async throws {
        guard let pid = pidOfApp(app) else {
            throw AXorcistBridgeError.appNotFound(app)
        }
        let axApp = AXUIElementCreateApplication(pid)
        guard let axEl = findElement(in: axApp, label: target) else {
            throw AXorcistBridgeError.elementNotFound(app: app, element: target)
        }
        AXUIElementSetAttributeValue(axEl, kAXValueAttribute as CFString, text as CFString)
    }

    func read(app: String, element: String) async throws -> String {
        guard let pid = pidOfApp(app) else {
            throw AXorcistBridgeError.appNotFound(app)
        }
        let axApp = AXUIElementCreateApplication(pid)
        guard let axEl = findElement(in: axApp, label: element) else {
            throw AXorcistBridgeError.elementNotFound(app: app, element: element)
        }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axEl, kAXValueAttribute as CFString, &value)
        guard result == .success, let string = value as? String else {
            throw AXorcistBridgeError.readFailed(element)
        }
        return string
    }

    func screenshot(app: String?, region: CGRect?) async throws -> Data {
        if let appName = app, let pid = pidOfApp(appName) {
            return try await captureWindow(pid: pid)
        } else {
            return try await captureScreen()
        }
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

    // MARK: - Private Helpers

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

    private func captureWindow(pid: pid_t) async throws -> Data {
        let scContent: SCShareableContent = try await SCShareableContent.current
        guard let window: SCWindow = scContent.windows.first(where: { $0.owningApplication?.processID == pid }) else {
            return try await captureScreen()
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try await captureWithFilter(filter)
    }

    private func captureScreen() async throws -> Data {
        let scContent: SCShareableContent = try await SCShareableContent.current
        guard let display: SCDisplay = scContent.displays.first else {
            throw AXorcistBridgeError.screenshotFailed
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await captureWithFilter(filter)
    }

    private func captureWithFilter(_ filter: SCContentFilter) async throws -> Data {
        let config: SCStreamConfiguration = SCStreamConfiguration()
        config.width = 1920
        config.height = 1080
        let image: CGImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        let rep: NSBitmapImageRep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw AXorcistBridgeError.screenshotFailed
        }
        return data
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
