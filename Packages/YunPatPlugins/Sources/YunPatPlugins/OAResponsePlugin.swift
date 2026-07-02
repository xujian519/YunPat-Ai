import Foundation
import YunPatCore

/// OA 答复插件 — L1 工具插件
///
/// 设计 §8 插件蓝图 #3：patent-oa
public struct OAResponsePlugin {
    public static let manifest = PluginManifest(
        id: "com.yunpat.plugin.oa-response",
        name: "OA 答复分析",
        version: "1.0.0",
        minAppVersion: "1.0.0",
        level: .tool,
        description: "解析审查意见通知书，三步法对比分析，辅助生成答复稿",
        author: "YunPat-Ai",
        permissions: [.fileRead, .networkAPI]
    )

    public static func capabilities() -> [CapabilityDefinition] {
        [
            CapabilityDefinition(
                name: "patent.oa.parse",
                displayName: "OA 解析",
                description: "解析审查意见通知书，提取驳回理由、对比文件、审查员意见",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .low, requiresNetwork: true, isIdempotent: true, typicalUseCases: ["OA解析", "审查意见分析"])
            ),
            CapabilityDefinition(
                name: "patent.oa.compare",
                displayName: "特征对比",
                description: "将权利要求与对比文件进行逐特征对比分析",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .medium, requiresNetwork: true, isIdempotent: false, typicalUseCases: ["特征对比", "三步法分析"])
            ),
            CapabilityDefinition(
                name: "patent.oa.response",
                displayName: "答复稿生成",
                description: "根据分析结果生成审查意见答复书",
                source: .plugin,
                permission: .perSession,
                metadata: CapabilityMetadata(
                    costLevel: .medium, requiresNetwork: true, isIdempotent: false, typicalUseCases: ["答复书撰写"])
            )
        ]
    }
}
