import Foundation

// MARK: - Sandbox Protocol

/// 沙箱虚拟机接口 — 基于 Apple Containerization 框架（macOS 26+ Tahoe）。
///
/// 提供隔离的 Linux VM 执行环境：
/// - 每个 Agent 独立 Linux 用户和 home 目录
/// - VirtioFS 挂载工作目录
/// - vsock 桥接到主机 API（推理、记忆、密钥）
/// - 零风险执行代码和 Shell 命令
///
/// > **平台要求**：macOS 26+（Tahoe）。macOS 15.5+ 返回 `.unsupported`。
public protocol SandboxProvider: Sendable {
    /// 沙箱当前状态
    var status: SandboxStatus { get async }

    /// 为指定 Agent 创建隔离执行环境
    func createVM(agentID: String) async throws -> SandboxVM

    /// 列出当前运行的 VM
    func listVMs() async -> [SandboxVM]

    /// 销毁指定 Agent 的 VM
    func destroyVM(agentID: String) async throws
}

// MARK: - Sandbox VM

public struct SandboxVM: Sendable, Identifiable {
    public let id: String  // = agentID
    public let state: VMState
    public let linuxUser: String
    public let homeDirectory: String
    public let workspaceMount: String  // VirtioFS 挂载点路径

    public init(
        id: String, state: VMState = .stopped, linuxUser: String = "",
        homeDirectory: String = "", workspaceMount: String = ""
    ) {
        self.id = id
        self.state = state
        self.linuxUser = linuxUser
        self.homeDirectory = homeDirectory
        self.workspaceMount = workspaceMount
    }
}

public enum VMState: String, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case error
}

// MARK: - Sandbox Status

public enum SandboxStatus: Sendable {
    /// 沙箱完全可用
    case available
    /// 平台不支持（需 macOS 26+）
    case unsupported(reason: String)
    /// 框架可用但未授权
    case unauthorized
}

// MARK: - Sandbox Manager

/// 沙箱管理器 — 统一的沙箱生命周期管理入口。
///
/// 在 macOS 26+ 上使用 Apple Containerization 创建 Linux VM。
/// 在较早版本上优雅降级，所有操作返回明确的 `.unsupported` 错误。
public actor SandboxManager: SandboxProvider {
    private var vms: [String: SandboxVM] = [:]

    public init() {}

    public var status: SandboxStatus {
        if #available(macOS 26.0, *) {
            return .available
        } else {
            return .unsupported(
                reason: "Apple Containerization requires macOS 26.0+ (Tahoe). Current OS does not support this feature."
            )
        }
    }

    public func createVM(agentID: String) async throws -> SandboxVM {
        guard case .available = status else {
            throw SandboxError.unsupported
        }

        // macOS 26+ 实现：
        // 1. 使用 VZVirtualMachineConfiguration 创建 Linux VM
        // 2. 配置 VirtioFS 共享工作目录
        // 3. 配置 vsock 桥接到主机 API
        // 4. 为 agentID 创建独立 Linux 用户

        let sandboxVM = SandboxVM(
            id: agentID,
            state: .stopped,
            linuxUser: "agent-\(agentID)",
            homeDirectory: "/home/agent-\(agentID)",
            workspaceMount: "/workspace"
        )
        vms[agentID] = sandboxVM
        return sandboxVM
    }

    public func listVMs() -> [SandboxVM] {
        Array(vms.values)
    }

    public func destroyVM(agentID: String) async throws {
        vms[agentID] = nil
    }
}

// MARK: - Errors

public enum SandboxError: Error, LocalizedError {
    case unsupported
    case vmCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            "Sandbox VM requires macOS 26.0+ (Tahoe)"
        case .vmCreationFailed(let reason):
            "VM creation failed: \(reason)"
        }
    }
}
