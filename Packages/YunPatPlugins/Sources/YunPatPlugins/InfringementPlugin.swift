import Foundation
import YunPatCore

/// 侵权分析插件 — L1 工具插件
///
/// 设计 §8 插件蓝图 #4：patent-infringement
public struct InfringementPlugin {
    public static let manifest = PluginManifest(
        id: "com.yunpat.plugin.infringement",
        name: "侵权分析",
        version: "1.0.0",
        minAppVersion: "1.0.0",
        level: .tool,
        description: "技术特征对比表 + 等同分析 + 全面覆盖原则判定",
        author: "YunPat-Ai",
        permissions: [.fileRead, .networkAPI]
    )

    public static func capabilities() -> [CapabilityDefinition] {
        [
            CapabilityDefinition(
                name: "patent.infringement.feature-table",
                displayName: "特征对比表",
                description: "生成涉案专利与被控侵权产品的逐特征对比表",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(costLevel: .low, requiresNetwork: true, isIdempotent: true, typicalUseCases: ["特征对比", "侵权分析"])
            ),
            CapabilityDefinition(
                name: "patent.infringement.equivalence",
                displayName: "等同分析",
                description: "等同特征判定：三基本一无需原则（基本相同手段/功能/效果，无需创造性劳动）",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(costLevel: .medium, requiresNetwork: true, isIdempotent: false, typicalUseCases: ["等同侵权", "等同特征分析"])
            ),
        ]
    }
}
