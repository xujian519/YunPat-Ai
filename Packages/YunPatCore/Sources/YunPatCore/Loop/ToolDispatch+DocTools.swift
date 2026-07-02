import CoreGraphics
import Foundation

// MARK: - 文档工具 TypedTool 实现 & 注册

extension ToolDispatch {

    func registerDocTools() {
        let pdfInfo: GetPDFInfoTool = GetPDFInfoTool()
        handlers[pdfInfo.name] = pdfInfo.handler
        toolSpecs[pdfInfo.name] = ToolSpec(name: pdfInfo.name, description: pdfInfo.description)

        let pdfRender: RenderPDFPageTool = RenderPDFPageTool()
        handlers[pdfRender.name] = pdfRender.handler
        toolSpecs[pdfRender.name] = ToolSpec(name: pdfRender.name, description: pdfRender.description)
    }
}

// MARK: - PDF Info Tool

/// 获取 PDF 元数据
private struct GetPDFInfoTool: TypedTool {
    let name: String = "pdf_get_info"
    let description: String = "获取 PDF 文件的元数据：页数、尺寸、加密状态。先调用此工具了解 PDF 总页数，再使用 pdf_render_page 渲染指定页。"

    struct Args: Decodable, Sendable {
        let pdf_path: String
        let _context_folder: String?
    }

    func execute(input: Args, context: ToolContext) async throws -> ToolResponse {
        let folder: String = input._context_folder ?? context.projectFolder
        guard !folder.isEmpty else {
            return ToolResponse.errResp(code: .invalidArgs, message: "pdf_path 是必填参数")
        }
        do {
            let contextFolder: String? = folder.isEmpty ? nil : folder
            let info: PDFRenderer.PageInfo = try PDFRenderer.getInfo(
                from: input.pdf_path, contextFolder: contextFolder
            )
            let encoder: JSONEncoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data: Data = try? encoder.encode(info),
                let dict: [String: Any] = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return ToolResponse.errResp(code: .internalError, message: "JSON 编码失败")
            }
            let jsonData: Data = try JSONSerialization.data(withJSONObject: dict)
            let jsonValue: JSONValue = try JSONDecoder().decode(JSONValue.self, from: jsonData)
            return ToolResponse.okResp(data: jsonValue)
        } catch {
            return ToolResponse.errResp(code: .readError, message: error.localizedDescription)
        }
    }
}

// MARK: - PDF Render Page Tool

/// 渲染 PDF 页面为图像（供 OCR/文档检测使用）
private struct RenderPDFPageTool: TypedTool {
    let name: String = "pdf_render_page"
    let description: String = "渲染 PDF 指定页为图像。与 detect_text / detect_document 配合使用。返回渲染后的图像临时路径。"

    struct Args: Decodable, Sendable {
        let pdf_path: String
        let page: Int?
        let dpi: Int?
        let output_path: String?
        let _context_folder: String?
    }

    func execute(input: Args, context: ToolContext) async throws -> ToolResponse {
        let folder: String = input._context_folder ?? context.projectFolder
        let page: Int = input.page ?? 1
        let dpi: Int = input.dpi ?? 300

        do {
            let cgImage: CGImage = try PDFRenderer.renderPage(
                from: input.pdf_path,
                contextFolder: folder.isEmpty ? nil : folder,
                page: page,
                dpi: dpi
            )

            let result: [String: JSONValue] = [
                "page": .number(Double(page)),
                "dpi": .number(Double(dpi)),
                "width": .number(Double(cgImage.width)),
                "height": .number(Double(cgImage.height)),
                "status": .string("rendered")
            ]
            return ToolResponse.okResp(data: .object(result))
        } catch {
            return ToolResponse.errResp(code: .readError, message: error.localizedDescription)
        }
    }
}
