import Foundation
import YunPatCore

/// 文档处理器插件 — L1 工具插件
///
/// 设计 §8 插件蓝图 #5：document-processor
public struct DocumentProcessorPlugin {
    public static let manifest = PluginManifest(
        id: "com.yunpat.plugin.document-processor",
        name: "文档处理",
        version: "1.0.0",
        minAppVersion: "1.0.0",
        level: .tool,
        description: "解析 PDF/Word/图片 多种格式，提取文本并转换为 Markdown",
        author: "YunPat-Ai",
        permissions: [.fileRead, .fileWrite]
    )

    public static func capabilities() -> [CapabilityDefinition] {
        [
            CapabilityDefinition(
                name: "document.parse.pdf",
                displayName: "PDF 解析",
                description: "提取 PDF 文本、图片、表格，支持 OCR 识别",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .low, requiresNetwork: false, isIdempotent: true, typicalUseCases: ["专利PDF提取", "文档解析"])
            ),
            CapabilityDefinition(
                name: "document.parse.word",
                displayName: "Word 解析",
                description: "提取 .doc/.docx 文本内容，保留基础格式",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .low, requiresNetwork: false, isIdempotent: true, typicalUseCases: ["Word文档读取"])
            ),
            CapabilityDefinition(
                name: "document.convert.markdown",
                displayName: "格式转换",
                description: "将任意文档转换为 Markdown 格式供 AI 分析",
                source: .plugin,
                permission: .always,
                metadata: CapabilityMetadata(
                    costLevel: .low, requiresNetwork: false, isIdempotent: true,
                    typicalUseCases: ["格式转换", "Markdown导出"])
            )
        ]
    }
}
