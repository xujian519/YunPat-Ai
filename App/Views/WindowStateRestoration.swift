import SwiftUI

/// NSWindowRestoration 状态保存 + AppStorage 持久化
///
/// 设计 §13 HIG 要求：退出重启无缝。
/// 注意：左/右侧面板宽度由 `ContentView` 中的 `@AppStorage("yunpat.sidebarWidth")` /
/// `@AppStorage("yunpat.rightPanelWidth")` 自动持久化与恢复，此处不重复管理。
/// NavigationSplitView 的侧栏宽度由系统自动持久化。
struct WindowStateRestoration: ViewModifier {
    @AppStorage("yunpat.leftDockVisible") private var leftDockVisible: Bool = true
    @AppStorage("yunpat.lastActiveTab") private var lastActiveTab: String = ""
    @AppStorage("yunpat.windowFrame") private var windowFrameData = Data()

    func body(content: Content) -> some View {
        content
            .onAppear {
                if let window = NSApp.keyWindow {
                    Self.restoreWindowState(for: window)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                if let window = notification.object as? NSWindow {
                    let frameStr = NSStringFromRect(window.frame)
                    UserDefaults.standard.set(frameStr.data(using: .utf8), forKey: "yunpat.windowFrame")
                }
            }
    }

    static func restoreWindowState(for window: NSWindow) {
        guard let data = UserDefaults.standard.data(forKey: "yunpat.windowFrame"),
            let frameStr = String(data: data, encoding: .utf8)
        else { return }
        let frame = NSRectFromString(frameStr)
        if !frame.isEmpty {
            window.setFrame(frame, display: true)
        }
    }
}

extension View {
    func withWindowRestoration() -> some View {
        modifier(WindowStateRestoration())
    }
}
