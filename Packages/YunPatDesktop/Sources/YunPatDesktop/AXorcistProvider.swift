import AppKit

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
public final class AppKitAXorcist: AXorcistProvider, @unchecked Sendable {

    public init() {}

    public func click(app: String, element: String) async throws {
        guard let axApp = findApp(app), let axEl = findElement(in: axApp, label: element) else {
            throw AXorcistError.elementNotFound(app: app, element: element)
        }
        AXUIElementPerformAction(axEl, kAXPressAction as CFString)
    }

    public func type(app: String, text: String, target: String) async throws {
        guard let axApp = findApp(app), let axEl = findElement(in: axApp, label: target) else {
            throw AXorcistError.elementNotFound(app: app, element: target)
        }
        AXUIElementSetAttributeValue(axEl, kAXValueAttribute as CFString, text as CFString)
    }

    public func read(app: String, element: String) async throws -> String {
        guard let axApp = findApp(app), let axEl = findElement(in: axApp, label: element) else {
            throw AXorcistError.elementNotFound(app: app, element: element)
        }
        var value: CFTypeRef?
        let result: CFString = AXUIElementCopyAttributeValue(axEl, kAXValueAttribute as CFString, &value)
        guard result == .success, let string = value as? String else {
            throw AXorcistError.readFailed(element: element)
        }
        return string
    }

    public func screenshot(app: String?, region: CGRect?) async throws -> Data {
        let image: CGImage
        if let appName = app, let pid = pidOfApp(appName) {
            let appElement = AXUIElementCreateApplication(pid)
            var size: CFTypeRef?
            AXUIElementCopyAttributeValue(appElement, kAXSizeAttribute as CFString, &size)
            // Simplified: screenshot via CGWindowList
            guard
                let listImage = CGWindowListCreateImage(
                    .null, .optionOnScreenOnly, CGWindowID(pid), .boundsIgnoreFraming)
            else {
                throw AXorcistError.screenshotFailed
            }
            image = listImage
        } else {
            guard
                let screenImage = CGWindowListCreateImage(
                    .null, .optionOnScreenOnly, kCGNullWindowID, .boundsIgnoreFraming)
            else {
                throw AXorcistError.screenshotFailed
            }
            image = screenImage
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw AXorcistError.screenshotFailed
        }
        return pngData
    }

    private func findApp(_ name: String) -> AXUIElement? {
        guard let pid = pidOfApp(name) else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    private func findElement(in axApp: AXUIElement, label: String) -> AXUIElement? {
        var query: CFTypeRef?
        let criteria: CFDictionary = [kAXTitleAttribute: label] as CFDictionary
        AXUIElementCopyAttributeValue(axApp, kAXChildrenAttribute as CFString, &query)
        // Simplified: recursive search
        return nil  // Stub — full implementation requires AX tree traversal
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
