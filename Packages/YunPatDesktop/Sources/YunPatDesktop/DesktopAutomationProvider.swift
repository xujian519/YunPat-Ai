import Foundation

public struct AppIdentifier: Sendable {
    public let bundleID: String
    public let displayName: String
    public init(bundleID: String, displayName: String) {
        self.bundleID = bundleID
        self.displayName = displayName
    }
}

public struct ElementLocator: Sendable {
    public let role: String
    public let description: String
    public init(role: String, description: String = "") {
        self.role = role
        self.description = description
    }
}

public protocol DesktopAutomationProvider: Sendable {
    func click(app: AppIdentifier, element: ElementLocator) async throws
    func type(app: AppIdentifier, text: String, target: ElementLocator) async throws
    func read(app: AppIdentifier, element: ElementLocator) async throws -> String
    var isAccessibilityEnabled: Bool { get async }
}
