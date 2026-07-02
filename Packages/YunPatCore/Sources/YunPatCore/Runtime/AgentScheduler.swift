import Foundation
import YunPatNetworking

// MARK: - Sub-Agent Summary

/// waitAll / collectSummaries 返回的轻量摘要
public struct SubAgentSummary: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let status: String
    public let resultSummary: String
    public let durationMs: Int

    public init(id: String, name: String, status: String, resultSummary: String = "", durationMs: Int = 0) {
        self.id = id
        self.name = name
        self.status = status
        self.resultSummary = resultSummary
        self.durationMs = durationMs
    }
}

// MARK: - Spawn Parameters

public struct SpawnParams: Sendable {
    public let name: String
    public let prompt: String
    public let projectFolder: String
    public let maxIterations: Int
    public let toolGroupIDs: Set<String>?
    public let modelRouter: ModelRouter
    public let provider: ModelProvider

    public init(
        name: String, prompt: String, projectFolder: String = "", maxIterations: Int = 10,
        toolGroupIDs: Set<String>? = nil, modelRouter: ModelRouter, provider: ModelProvider
    ) {
        self.name = name
        self.prompt = prompt
        self.projectFolder = projectFolder
        self.maxIterations = maxIterations
        self.toolGroupIDs = toolGroupIDs
        self.modelRouter = modelRouter
        self.provider = provider
    }
}

// MARK: - Agent Scheduler Protocol

public protocol AgentScheduler: Sendable {
    @discardableResult
    func spawn(params: SpawnParams) async -> String
    func waitAll(timeout: TimeInterval) async -> [SubAgentSummary]
    func cancelAll() async
    var activeCount: Int { get async }
    func collectSummaries() async -> [SubAgentSummary]
}

// MARK: - Tool Dispatcher Protocol

/// `dispatch` 的 input 用 `[String: String]` 替代 `[String: Any]`，保证 Sendable。
public protocol ToolDispatcher: Sendable {
    func dispatch(name: String, input: [String: String], ctx: ToolContext) async -> ToolHandlerResult
    var registeredTools: [String] { get async }
    func isReadOnly(name: String) -> Bool
}

// MARK: - Mock Implementations

/// 非 actor Mock，用 NSLock 保护状态，避免 ConformanceIsolation
public final class MockAgentScheduler: AgentScheduler, @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var _spawns: [(name: String, prompt: String)] = []
    private var _cancelled: Bool = false
    public var mockActiveCount: Int = 0
    public var activeCount: Int { mockActiveCount }
    public var spawns: [(name: String, prompt: String)] { lock.withLock { _spawns } }
    public var cancelled: Bool { lock.withLock { _cancelled } }

    public func spawn(params: SpawnParams) async -> String {
        lock.withLock { _spawns.append((params.name, params.prompt)) }
        mockActiveCount += 1
        return "Mock spawned '\(params.name)'"
    }

    public func waitAll(timeout: TimeInterval) async -> [SubAgentSummary] {
        mockActiveCount = 0
        return lock.withLock {
            _spawns.map { SubAgentSummary(id: UUID().uuidString, name: $0.name, status: "completed") }
        }
    }

    public func cancelAll() async {
        lock.withLock { _cancelled = true }
        mockActiveCount = 0
    }

    public func collectSummaries() async -> [SubAgentSummary] {
        lock.withLock {
            _spawns.map { SubAgentSummary(id: UUID().uuidString, name: $0.name, status: "completed") }
        }
    }
}

/// 非 actor Mock，`dispatchLog` 用 NSLock 保护
public final class MockToolDispatcher: ToolDispatcher, @unchecked Sendable {
    private let preloaded: [String: ToolHandler]
    private let lock: NSLock = NSLock()
    private var _dispatchLog: [(String, [String: String])] = []

    public var dispatchLog: [(String, [String: String])] { lock.withLock { _dispatchLog } }

    public init(handlers: [String: ToolHandler] = [:]) {
        self.preloaded = handlers
    }

    public var registeredTools: [String] { Array(preloaded.keys) }

    public func dispatch(name: String, input: [String: String], ctx: ToolContext) async -> ToolHandlerResult {
        lock.withLock { _dispatchLog.append((name, input)) }
        if let handler = preloaded[name] {
            // 注意: handler 仍然接收 [String: Any]，此处桥接
            let anyInput: [String: Any] = input
            return await handler(name, anyInput, ctx)
        }
        return .handled("[mock] tool '\(name)' executed")
    }

    public func isReadOnly(name: String) -> Bool { false }
}
