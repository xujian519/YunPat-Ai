import Foundation
import AppKit
import ApplicationServices

public actor AXorcistProvider: DesktopAutomationProvider {
    public init() {}

    public var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    public func click(app: AppIdentifier, element: ElementLocator) async throws {
        guard let appEl = findApp(app) else { throw AXError.appNotFound }
        guard let target = findElement(in: appEl, locator: element) else { throw AXError.elementNotFound }
        guard AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else { throw AXError.actionFailed }
    }

    public func type(app: AppIdentifier, text: String, target: ElementLocator) async throws {
        guard let appEl = findApp(app) else { throw AXError.appNotFound }
        guard let el = findElement(in: appEl, locator: target) else { throw AXError.elementNotFound }
        guard AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, text as CFTypeRef) == .success else { throw AXError.actionFailed }
    }

    public func read(app: AppIdentifier, element: ElementLocator) async throws -> String {
        guard let appEl = findApp(app) else { throw AXError.appNotFound }
        guard let target = findElement(in: appEl, locator: element) else { throw AXError.elementNotFound }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target, kAXValueAttribute as CFString, &value) == .success else { throw AXError.actionFailed }
        return value as? String ?? ""
    }

    private func findApp(_ id: AppIdentifier) -> AXUIElement? {
        guard let target = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id.bundleID }) else { return nil }
        return AXUIElementCreateApplication(target.processIdentifier)
    }

    private func findElement(in root: AXUIElement, locator: ElementLocator) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return nil }
        for child in children {
            var role: CFTypeRef?, desc: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &desc)
            if (role as? String) == locator.role,
               (locator.description.isEmpty || (desc as? String)?.contains(locator.description) == true) {
                return child
            }
        }
        return nil
    }
}

public enum AXError: Error {
    case appNotFound
    case elementNotFound
    case actionFailed
}
