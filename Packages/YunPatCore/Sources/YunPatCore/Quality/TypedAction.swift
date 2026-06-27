import Foundation

public protocol TypedAction: Sendable {
    associatedtype Payload: Sendable
    var payload: Payload { get }
    static var actionName: String { get }
}

public actor ActionDispatcher {
    private var handlers: [String: [(Any) async -> Void]] = [:]

    public init() {}

    public func on<A: TypedAction>(_ type: A.Type, handler: @escaping (A.Payload) async -> Void) {
        let key = A.actionName
        if handlers[key] == nil { handlers[key] = [] }
        handlers[key]?.append { if let p = $0 as? A.Payload { await handler(p) } }
    }

    public func dispatch<A: TypedAction>(_ action: A) async {
        for handler in handlers[A.actionName] ?? [] {
            await handler(action.payload)
        }
    }
}

public struct NewTabAction: TypedAction {
    public let payload: Void = ()
    public static let actionName = "tab.new"
}

public struct CloseTabAction: TypedAction {
    public let payload: UUID
    public static let actionName = "tab.close"
    public init(tabID: UUID) { self.payload = tabID }
}

public struct SendMessageAction: TypedAction {
    public let payload: String
    public static let actionName = "chat.send"
    public init(message: String) { self.payload = message }
}
