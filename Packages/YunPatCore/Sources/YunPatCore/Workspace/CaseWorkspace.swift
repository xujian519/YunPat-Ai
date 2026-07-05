import Foundation

// MARK: - CaseWorkspaceStatus

/// 案件工作区生命周期状态
public enum CaseWorkspaceStatus: String, Sendable, Codable, CaseIterable {
    case active = "进行中"
    case onHold = "暂停"
    case closed = "已结案"
}

// MARK: - CaseWorkspace

/// 案件工作区 — 每个 patent case 的隔离工作空间。
///
/// 与 `ChatTab.workspacePath` 解耦存储：工作区元数据持久化在 UserDefaults，
/// 文件系统路径仅作为引用，便于在 Sandbox 中通过 security-scoped bookmark 后续扩展。
public struct CaseWorkspace: Identifiable, Sendable, Codable {
    public let id: UUID
    public let caseId: String
    public var title: String
    public var workspacePath: String?
    public var tags: [String]
    public var status: CaseWorkspaceStatus
    public var notes: String
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        caseId: String,
        title: String,
        workspacePath: String? = nil,
        tags: [String] = [],
        status: CaseWorkspaceStatus = .active,
        notes: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.caseId = caseId
        self.title = title
        self.workspacePath = workspacePath
        self.tags = tags
        self.status = status
        self.notes = notes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
    }
}
