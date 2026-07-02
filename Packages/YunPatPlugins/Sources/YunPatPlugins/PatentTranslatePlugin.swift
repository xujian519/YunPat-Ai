import Foundation
import YunPatCore

/// 专利翻译插件 — L1 工具插件
///
/// 设计 §8 插件蓝图 #6：patent-translate
public struct PatentTranslatePlugin {
    public static let manifest = PluginManifest(
        id: "com.yunpat.plugin.patent-translate",
        name: "专利翻译",
        version: "1.0.0",
        minAppVersion: "1.0.0",
        level: .tool,
        description: "中英专利互译，内置专利术语库保证翻译规范性",
        author: "YunPat-Ai",
        permissions: [.networkAPI]
    )

    public static func capabilities() -> [CapabilityDefinition] {
        [
            CapabilityDefinition(
                name: "patent.translate.cn2en",
                displayName: "中译英",
                description: "将中国专利文本翻译为英文，使用专利标准术语",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .medium, requiresNetwork: true, isIdempotent: false, typicalUseCases: ["PCT申请", "海外布局"])
            ),
            CapabilityDefinition(
                name: "patent.translate.en2cn",
                displayName: "英译中",
                description: "将英文专利文本翻译为中文，保留技术术语准确性",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .medium, requiresNetwork: true, isIdempotent: false,
                    typicalUseCases: ["外国专利阅读", "对比文件分析"])
            ),
            CapabilityDefinition(
                name: "patent.translate.terms",
                displayName: "术语库查询",
                description: "查询专利术语的标准翻译（中英双向）",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .free, requiresNetwork: false, isIdempotent: true, typicalUseCases: ["术语确认"])
            )
        ]
    }
}
