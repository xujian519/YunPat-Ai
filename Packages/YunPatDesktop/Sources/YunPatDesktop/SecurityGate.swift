import Foundation

public enum PermissionLevel: Sendable {
    case always
    case perSession
    case perCall
    case never
}

public struct OperationLog: Sendable {
    public let timestamp: Date
    public let capability: String
    public let tool: String
    public let result: String
    public init(timestamp: Date = Date(), capability: String, tool: String, result: String) {
        self.timestamp = timestamp
        self.capability = capability
        self.tool = tool
        self.result = result
    }
}

public actor SecurityGate {
    private var grants: Set<String> = []
    private var callTokens: Set<String> = []
    public private(set) var auditLog: [OperationLog] = []

    public init() {}

    public func check(_ capability: String, level: PermissionLevel) -> Bool {
        switch level {
        case .always: return true
        case .never: return false
        case .perSession: return grants.contains(capability)
        case .perCall: return callTokens.remove(capability) != nil
        }
    }

    public func grant(_ capability: String, level: PermissionLevel) {
        switch level {
        case .perSession: grants.insert(capability)
        case .perCall: callTokens.insert(capability)
        default: break
        }
    }

    public func record(_ log: OperationLog) {
        auditLog.append(log)
    }
}
