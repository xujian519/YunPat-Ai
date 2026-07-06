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

/// 基础实现（macOS Accessibility API）
public actor AppKitAXorcist: AXorcistProvider {

    public init() {}

    public func click(app: String, element: String) async throws {
        guard let axApp = findApp(app) else {
            throw AXorcistError.elementNotFound(app: app, element: element)
        }
        guard let axEl = findElement(in: axApp, label: element) else {
            throw AXorcistError.elementNotFound(app: app, element: element)
        }
        AXUIElementPerformAction(axEl, kAXPressAction as CFString)
    }

    public func type(app: String, text: String, target: String) async throws {
        guard let axApp = findApp(app) else {
            throw AXorcistError.elementNotFound(app: app, element: target)
        }
        guard let axEl = findElement(in: axApp, label: target) else {
            throw AXorcistError.elementNotFound(app: app, element: target)
        }
        AXUIElementSetAttributeValue(axEl, kAXValueAttribute as CFString, text as CFString)
    }

    public func read(app: String, element: String) async throws -> String {
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

    /// 递归搜索 AX 树，匹配 title/value/description 包含 label 的元素
    private func findElement(in axApp: AXUIElement, label: String) -> AXUIElement? {
        searchAXTree(axApp, target: label, depth: 0, maxDepth: 8)
    }

    private func searchAXTree(_ element: AXUIElement, target: String, depth: Int, maxDepth: Int) -> AXUIElement? {
        if depth > maxDepth { return nil }

        // 检查当前元素属性是否匹配
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
            if result == .success, let str = value as? String {
                if str.localizedCaseInsensitiveContains(target) {
                    return element
                }
            }
        }

        // 递归搜索子元素
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
}

public enum AXorcistError: Error, LocalizedError {
    case elementNotFound(app: String, element: String)
    case readFailed(element: String)
    case screenshotFailed
    case appNotAllowed(String)

    public var errorDescription: String? {
        switch self {
        case .elementNotFound(let app, let element): "未找到 \(app) 中的 \(element)"
        case .readFailed(let element): "读取 \(element) 失败"
        case .screenshotFailed: "截图失败"
        case .appNotAllowed(let name): "\(name) 不在白名单中"
        }
    }
}
