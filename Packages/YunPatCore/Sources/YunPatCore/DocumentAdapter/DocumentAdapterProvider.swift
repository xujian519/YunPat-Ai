import Foundation

/// 文档适配器提供者 — 一键获取已注册全部内置适配器的 Registry
///
/// 工厂方法返回预先注册了所有内置适配器的实例，
/// 上层代码无需关心适配器的注册顺序和依赖。
public enum DocumentAdapterProvider {

    /// 创建预注册了所有内置适配器的 Registry
    ///
    /// 注册的适配器（按优先级排列）：
    /// 1. PDFDocumentAdapter — PDF (PDFKit)
    /// 2. PlainTextDocumentAdapter — TXT/MD/JSON/XML/YAML...
    /// 3. CSVDocumentAdapter — CSV/TSV
    /// 4. OfficeDocumentAdapter — DOCX/XLSX/PPTX
    public static func createDefaultRegistry() async -> DocumentAdapterRegistry {
        let registry = DocumentAdapterRegistry()
        await registry.registerAll(
            PDFDocumentAdapter(),
            PlainTextDocumentAdapter(),
            CSVDocumentAdapter(),
            OfficeDocumentAdapter()
        )
        return registry
    }
}
