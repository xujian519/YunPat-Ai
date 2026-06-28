import SwiftUI

/// NSWindowRestoration 状态保存 + AppStorage 持久化
///
/// 设计 §13 HIG 要求：退出重启无缝
struct WindowStateRestoration: ViewModifier {
    @AppStorage("yunpat.sidebarCollapsed") private var sidebarCollapsed = false
    @AppStorage("yunpat.lastActiveTab") private var lastActiveTab = ""
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
              let frameStr = String(data: data, encoding: .utf8) else { return }
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
