import Foundation
import YunPatCore

/// 专利检索插件 — L1 工具插件
///
/// 设计 §8 插件蓝图 #1：patent-search
/// 注册到 CapabilityRegistry，提供 Google Patents / CNIPA 检索能力
public struct PatentSearchPlugin {
    public static let manifest = PluginManifest(
        id: "com.yunpat.plugin.patent-search",
        name: "专利检索",
        version: "1.0.0",
        minAppVersion: "1.0.0",
        level: .tool,
        description: "通过 Google Patents 和 CNIPA 检索全球专利文献",
        author: "YunPat-Ai",
        permissions: [.networkAPI]
    )

    public static func capabilities() -> [CapabilityDefinition] {
        [
            CapabilityDefinition(
                name: "patent.search.google",
                displayName: "Google Patents 检索",
                description: "使用 Google Patents API 检索全球专利文献，支持布尔检索式和关键词",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .low,
                    requiresNetwork: true,
                    isIdempotent: true,
                    typicalUseCases: ["专利检索", "对比文件查找", "技术领域调研"]
                )
            ),
            CapabilityDefinition(
                name: "patent.search.cnipa",
                displayName: "CNIPA 检索",
                description: "在中国国家知识产权局公布公告系统中检索专利",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .low,
                    requiresNetwork: true,
                    isIdempotent: true,
                    typicalUseCases: ["中国专利检索", "法律状态查询"]
                )
            ),
        ]
    }
}
