import AppKit
import ScreenCaptureKit

/// AXorcist 桌面自动化协议层 — 操控 Mac 应用的 Accessibility API
///
/// 设计 §5：三层能力（AXorcist / Shell / 文件系统）
public protocol AXorcistProvider: Sendable {
    func click(app: String, element: String) async throws
    func type(app: String, text: String, target: String) async throws
    func read(app: String, element: String) async throws -> String
    func screenshot(app: String?, region: CGRect?) async throws -> Data
}

/// 基础实现（macOS Accessibility API），带 AX→CGEvent→HID 三级降级路由链
///
/// 路由链：
///   1. AXUIElementPerformAction / AXUIElementSetAttributeValue（纯后台）
///   2. CGEvent.postToPid（不移动光标）
///   3. CGEvent.post(tap: .cghidEventTap)（移动光标，最后手段）
public actor AppKitAXorcist: AXorcistProvider {

    public private(set) var lastRoute: InputRoute = .accessibility

    public var lastRouteDescription: String { lastRoute.rawValue }

    public init() {}

    public func click(app: String, element: String) async throws {
        guard let axApp = findApp(app) else {
            throw AXorcistError.elementNotFound(app: app, element: element)
        }
        guard let axEl = findElement(in: axApp, label: element) else {
            throw AXorcistError.elementNotFound(app: app, element: element)
        }

        // Level 1: AXPress
        let pressResult = AXUIElementPerformAction(axEl, kAXPressAction as CFString)
        if pressResult == .success {
            lastRoute = .accessibility
            return
        }

        // Level 2 & 3: fallback to CGEvent
        guard let position = getElementScreenCenter(axEl), let pid = pidOfAXElement(axEl) else {
            throw AXorcistError.elementNotInteractive(app: app, element: element)
        }

        let cgResult = BackgroundRouter.shared.click(point: position, pid: pid)
        if cgResult.success {
            lastRoute = cgResult.route
            return
        }

        let hidResult = BackgroundRouter.shared.clickHID(point: position)
        lastRoute = hidResult.route
        if !hidResult.success {
            throw AXorcistError.clickFailed(app: app, element: element)
        }
    }

    public func type(app: String, text: String, target: String) async throws {
        guard let axApp = findApp(app) else {
            throw AXorcistError.elementNotFound(app: app, element: target)
        }
        guard let axEl = findElement(in: axApp, label: target) else {
            throw AXorcistError.elementNotFound(app: app, element: target)
        }

        // Level 1: AXSetAttributeValue
        let setResult = AXUIElementSetAttributeValue(axEl, kAXValueAttribute as CFString, text as CFString)
        if setResult == .success {
            lastRoute = .accessibility
            return
        }

        // Level 2 & 3: fallback to CGEvent keyboard per-pid
        guard let pid = pidOfAXElement(axEl) else {
            throw AXorcistError.elementNotInteractive(app: app, element: target)
        }
        let result = BackgroundRouter.shared.type(text: text, pid: pid)
        lastRoute = result.route
        if !result.success {
            throw AXorcistError.typeFailed(app: app, element: target)
        }
    }

    public func read(app: String, element: String) async throws -> String {
        lastRoute = .accessibility
        guard let axApp = findApp(app) else {
            throw AXorcistError.elementNotFound(app: app, element: element)
        }
        guard let axEl = findElement(in: axApp, label: element) else {
            throw AXorcistError.elementNotFound(app: app, element: element)
        }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axEl, kAXValueAttribute as CFString, &value)
        guard result == .success, let string = value as? String else {
            throw AXorcistError.readFailed(element: element)
        }
        return string
    }

    public func screenshot(app: String?, region: CGRect?) async throws -> Data {
        if let appName = app, let pid = pidOfApp(appName) {
            return try await captureWindow(pid: pid, region: region)
        } else {
            return try await captureScreen(region: region)
        }
    }

    // MARK: - Screen Capture (ScreenCaptureKit)

    private func captureWindow(pid: pid_t, region: CGRect?) async throws -> Data {
        let content: SCShareableContent = try await SCShareableContent.current
        guard let window = content.windows.first(where: { $0.owningApplication?.processID == pid }) else {
            throw AXorcistError.screenshotFailed
        }
        let filter: SCContentFilter = SCContentFilter(desktopIndependentWindow: window)
        return try await captureWithFilter(filter, region: region)
    }

    private func captureScreen(region: CGRect?) async throws -> Data {
        let content: SCShareableContent = try await SCShareableContent.current
        guard let display: SCDisplay = content.displays.first else {
            throw AXorcistError.screenshotFailed
        }
        let filter: SCContentFilter = SCContentFilter(display: display, excludingWindows: [])
        return try await captureWithFilter(filter, region: region)
    }

    private func captureWithFilter(_ filter: SCContentFilter, region: CGRect?) async throws -> Data {
        let config = SCStreamConfiguration()
        if let region {
            config.width = Int(region.width)
            config.height = Int(region.height)
        } else {
            config.width = 1920
            config.height = 1080
        }
        let image: CGImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        let rep = NSBitmapImageRep(cgImage: image)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw AXorcistError.screenshotFailed
        }
        return pngData
    }

    // MARK: - AX Tree Helpers

    private func findApp(_ name: String) -> AXUIElement? {
        guard let pid = pidOfApp(name) else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    private func findElement(in axApp: AXUIElement, label: String) -> AXUIElement? {
        searchAXTree(axApp, target: label, depth: 0, maxDepth: 8)
    }

    private func searchAXTree(_ element: AXUIElement, target: String, depth: Int, maxDepth: Int) -> AXUIElement? {
        if depth > maxDepth { return nil }

        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
            if result == .success, let str = value as? String {
                if str.localizedCaseInsensitiveContains(target) {
                    return element
                }
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
        let running: [NSRunningApplication] = NSWorkspace.shared.runningApplications
        return running.first(where: { $0.localizedName?.localizedCaseInsensitiveContains(name) == true })?
            .processIdentifier
    }

    /// 获取 AX 元素的屏幕中心点
    private func getElementScreenCenter(_ element: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        // swiftlint:disable:next force_cast
        let positionValue: AXValue? = positionRef as! AXValue?
        guard let posVal = positionValue else { return nil }
        var point: CGPoint = .zero
        guard AXValueGetValue(posVal, .cgPoint, &point) else { return nil }

        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        // swiftlint:disable:next force_cast
        let sizeValue: AXValue? = sizeRef as! AXValue?
        guard let sizeVal = sizeValue else { return point }
        var size: CGSize = .zero
        guard AXValueGetValue(sizeVal, .cgSize, &size) else { return point }

        return CGPoint(x: point.x + size.width / 2, y: point.y + size.height / 2)
    }

    /// 获取 AX 元素的进程 ID
    private func pidOfAXElement(_ element: AXUIElement) -> pid_t? {
        var pid: pid_t = -1
        let result = AXUIElementGetPid(element, &pid)
        return result == .success ? pid : nil
    }
}

public enum AXorcistError: Error, LocalizedError {
    case elementNotFound(app: String, element: String)
    case readFailed(element: String)
    case screenshotFailed
    case appNotAllowed(String)
    case elementNotInteractive(app: String, element: String)
    case clickFailed(app: String, element: String)
    case typeFailed(app: String, element: String)

    public var errorDescription: String? {
        switch self {
        case .elementNotFound(let app, let element): "未找到 \(app) 中的 \(element)"
        case .readFailed(let element): "读取 \(element) 失败"
        case .screenshotFailed: "截图失败"
        case .appNotAllowed(let name): "\(name) 不在白名单中"
        case .elementNotInteractive(let app, let element): "\(app) 中的 \(element) 无法获取交互坐标"
        case .clickFailed(let app, let element): "\(app) 中的 \(element) 点击失败（所有路由均失败）"
        case .typeFailed(let app, let element): "\(app) 中的 \(element) 输入文本失败（所有路由均失败）"
        }
    }
}
