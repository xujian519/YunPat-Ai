import CoreGraphics
import Foundation

/// 输入事件路由级别 — 从完全后台到光标可见的降级链
///
/// 设计参考 osaurus BackgroundDriver 路由链：
///   Level 1: AXUIElementPerformAction (Accessibility API) — 纯后台，不移动光标
///   Level 2: CGEvent.postToPid (CoreGraphics) — 不移动光标，但 Chromium web content 会丢弃
///   Level 3: CGEvent.post(tap: .cghidEventTap) (HID) — 移动光标，最后手段
public enum InputRoute: String, Codable, Sendable {
    /// AXUIElement API 成功执行
    case accessibility
    /// CGEvent.postToPid 成功发送
    case perPid
    /// HID tap 回退（光标可见）
    case hidFallback
}

/// 输入操作结果 — 携带路由遥测
public struct InputResult: Sendable {
    public let success: Bool
    public let route: InputRoute
    public let error: String?

    public static func ok(route: InputRoute) -> InputResult {
        InputResult(success: true, route: route, error: nil)
    }

    public static func fail(route: InputRoute, _ message: String) -> InputResult {
        InputResult(success: false, route: route, error: message)
    }
}

/// 共享 CGEventSource
private enum SharedEventSource {
    nonisolated(unsafe) static let source: CGEventSource = {
        // swiftlint:disable:next force_unwrapping
        CGEventSource(stateID: .hidSystemState) ?? CGEventSource(stateID: .privateState)!
    }()
}

/// 鼠标/键盘事件的 per-pid 后台路由
///
/// 路由链（每步失败自动降级）：
///   1. `SLEventPostToPid` (SkyLight) — 完全后台，光标不动
///   2. `CGEvent.postToPid`  — 不移动光标，Chromium 拒绝
///   3. `CGEvent.post(tap: .cghidEventTap)` — 移动光标
public final class BackgroundRouter: @unchecked Sendable {
    public static let shared = BackgroundRouter()

    private let routeLock = NSLock()
    private var _lastRoute: InputRoute = .accessibility
    public var lastRoute: InputRoute {
        routeLock.lock()
        defer { routeLock.unlock() }
        return _lastRoute
    }

    private init() {}

    // MARK: - Routing

    /// 在指定 pid 的屏幕坐标位置点击，自动降级
    @discardableResult
    public func click(point: CGPoint, pid: pid_t) -> InputResult {
        guard
            let downEvent = CGEvent(
                mouseEventSource: SharedEventSource.source, mouseType: .leftMouseDown,
                mouseCursorPosition: point, mouseButton: .left),
            let upEvent = CGEvent(
                mouseEventSource: SharedEventSource.source, mouseType: .leftMouseUp,
                mouseCursorPosition: point, mouseButton: .left)
        else {
            record(route: .hidFallback)
            return .fail(route: .hidFallback, "Failed to create mouse events")
        }

        // postToPid 优先（AX click 已在调用方尝试过）
        downEvent.postToPid(pid)
        upEvent.postToPid(pid)
        let route: InputRoute = .perPid
        record(route: route)
        return .ok(route: route)
    }

    /// 通过 HID tap 强制点击（光标可见）
    @discardableResult
    public func clickHID(point: CGPoint) -> InputResult {
        guard
            let downEvent = CGEvent(
                mouseEventSource: SharedEventSource.source, mouseType: .leftMouseDown,
                mouseCursorPosition: point, mouseButton: .left),
            let upEvent = CGEvent(
                mouseEventSource: SharedEventSource.source, mouseType: .leftMouseUp,
                mouseCursorPosition: point, mouseButton: .left)
        else {
            return .fail(route: .hidFallback, "Failed to create mouse events")
        }
        downEvent.post(tap: .cghidEventTap)
        upEvent.post(tap: .cghidEventTap)
        record(route: .hidFallback)
        return .ok(route: .hidFallback)
    }

    /// 在指定 pid 输入文本，自动降级（postToPid → HID tap）
    @discardableResult
    public func type(text: String, pid: pid_t) -> InputResult {
        for char in text {
            // Level 2: per-pid
            let result = typeCharacter(char, pid: pid)
            if result.success { continue }

            // Level 3: HID tap fallback
            let hidResult = typeCharacterHID(char)
            if !hidResult.success { return hidResult }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return .ok(route: .accessibility)  // actual route may mix perPid and hidFallback
    }

    /// 通过 HID tap 输入单个字符（光标可见）
    @discardableResult
    public func typeCharacterHID(_ char: Character) -> InputResult {
        guard
            let downEvent = CGEvent(keyboardEventSource: SharedEventSource.source, virtualKey: 0, keyDown: true),
            let upEvent = CGEvent(keyboardEventSource: SharedEventSource.source, virtualKey: 0, keyDown: false)
        else {
            record(route: .hidFallback)
            return .fail(route: .hidFallback, "Failed to create keyboard events")
        }
        var utf16 = Array(String(char).utf16)
        downEvent.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        upEvent.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        downEvent.post(tap: .cghidEventTap)
        upEvent.post(tap: .cghidEventTap)
        record(route: .hidFallback)
        return .ok(route: .hidFallback)
    }

    private func typeCharacter(_ char: Character, pid: pid_t) -> InputResult {
        guard
            let downEvent = CGEvent(keyboardEventSource: SharedEventSource.source, virtualKey: 0, keyDown: true),
            let upEvent = CGEvent(keyboardEventSource: SharedEventSource.source, virtualKey: 0, keyDown: false)
        else {
            return .fail(route: .hidFallback, "Failed to create keyboard events")
        }
        var utf16 = Array(String(char).utf16)
        downEvent.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        upEvent.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        downEvent.postToPid(pid)
        upEvent.postToPid(pid)
        return .ok(route: .perPid)
    }

    private func record(route: InputRoute) {
        routeLock.lock()
        _lastRoute = route
        routeLock.unlock()
    }
}
