import Foundation

/// mid-run load 的 pending specs 缓冲区
/// 工具 load 后立即可调（registry dispatch by name），但 schema 快照冻结到下一 user turn
public actor CapabilityLoadBuffer {
    public static let shared: CapabilityLoadBuffer = CapabilityLoadBuffer()
    private var pendingLoads: [String] = []

    private init() {}

    /// 记录一次 load（load 完成时调用）
    public func recordLoad(_ capabilityName: String) {
        pendingLoads.append(capabilityName)
    }

    /// 获取并清空 pending loads（下一 user turn 由 ContextEngine 调用）
    public func drain() -> [String] {
        let drained: [String] = pendingLoads
        pendingLoads.removeAll()
        return drained
    }

    /// 当前是否有 pending loads
    public var hasPending: Bool { !pendingLoads.isEmpty }
}
