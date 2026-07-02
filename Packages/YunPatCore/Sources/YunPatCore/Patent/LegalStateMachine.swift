import Foundation

public enum LegalState: String, Sendable, Codable {
    case idle
    case factFinding
    case factAnalysis
    case legalBasis
    case legalScope
    case searchIteration
    case articleSelection
    case factLocked
    case planning
    case executing
    case reviewing
    case completed
    case abandoned
}

public struct Checkpoint: Sendable, Codable {
    public let state: LegalState
    public let timestamp: Date
    public let description: String

    public init(state: LegalState, description: String = "") {
        self.state = state
        self.timestamp = Date()
        self.description = description
    }
}

public enum TransitionResult: Sendable {
    case success
    case failure(String)
}

public actor LegalStateMachine {
    private var _state: LegalState = .idle
    private var _checkpoints: [Checkpoint] = []
    private var _history: [TransitionRecord] = []

    public var currentState: LegalState { _state }
    public var checkpoints: [Checkpoint] { _checkpoints }
    public var history: [TransitionRecord] { _history }

    private let validTransitions: [LegalState: [LegalState]] = [
        .idle: [.factFinding, .factAnalysis],
        .factFinding: [.legalBasis, .idle],
        .factAnalysis: [.legalScope, .idle],
        .legalBasis: [.articleSelection, .planning, .factFinding],
        .legalScope: [.searchIteration, .factAnalysis],
        .searchIteration: [.factLocked, .legalScope],
        .articleSelection: [.planning, .legalBasis],
        .factLocked: [.planning, .searchIteration],
        .planning: [.executing, .factFinding, .legalBasis],
        .executing: [.reviewing, .planning],
        .reviewing: [.completed, .factFinding, .legalBasis, .planning],
        .completed: [],
        .abandoned: []
    ]

    public func transition(to target: LegalState, reason: String = "") -> TransitionResult {
        guard let allowed = validTransitions[_state], allowed.contains(target) else {
            return .failure("非法转移: \(_state) → \(target)")
        }
        _history.append(TransitionRecord(from: _state, to: target, reason: reason))
        _state = target
        _checkpoints.append(Checkpoint(state: target, description: reason))
        return .success
    }

    public func rollback(to targetState: LegalState, reason: String) -> TransitionResult {
        guard let index = _checkpoints.lastIndex(where: { $0.state == targetState }) else {
            return .failure("无检查点: \(targetState)")
        }
        _checkpoints = Array(_checkpoints[0...index])
        _state = targetState
        _history.append(TransitionRecord(from: _state, to: targetState, reason: "rollback: \(reason)"))
        return .success
    }

    public func complete() {
        _state = .completed
    }

    public func abandon(reason: String) {
        _history.append(TransitionRecord(from: _state, to: .abandoned, reason: reason))
        _state = .abandoned
    }
}

public struct TransitionRecord: Sendable {
    public let from: LegalState
    public let to: LegalState
    public let reason: String
    public init(from: LegalState, to: LegalState, reason: String) {
        self.from = from
        self.to = to
        self.reason = reason
    }
}
