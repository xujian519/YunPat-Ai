import Foundation
import YunPatCore

/// 权利要求撰写插件 — L2 功能插件
///
/// 设计 §8 插件蓝图 #2：patent-drafting
public struct ClaimDraftingPlugin {
    public static let manifest = PluginManifest(
        id: "com.yunpat.plugin.claim-drafting",
        name: "权利要求撰写",
        version: "1.0.0",
        minAppVersion: "1.0.0",
        level: .feature,
        description: "辅助起草符合中国专利法的权利要求书，含独立/从属权利要求布局",
        author: "YunPat-Ai",
        permissions: [.fileWrite]
    )

    public static func capabilities() -> [CapabilityDefinition] {
        [
            CapabilityDefinition(
                name: "patent.drafting.claims",
                displayName: "权利要求起草",
                description: "根据技术交底书自动起草独立和从属权利要求，支持其特征在于划界",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .medium, requiresNetwork: true, isIdempotent: false, typicalUseCases: ["权利要求撰写", "布局设计"])
            ),
            CapabilityDefinition(
                name: "patent.drafting.description",
                displayName: "说明书起草",
                description: "起草专利说明书五部分：技术领域、背景技术、发明内容、附图说明、具体实施方式",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .medium, requiresNetwork: true, isIdempotent: false, typicalUseCases: ["说明书撰写"])
            )
        ]
    }
}
