import Foundation
import SwiftSoup

// MARK: - Google Patents 客户端

/// Google Patents HTTP 客户端 — 纯网络请求，零浏览器依赖。
///
/// 通过 `patents.google.com` 获取专利全文信息，使用 SwiftSoup 解析 schema.org 微数据。
///
/// ```swift
/// let client = GooglePatentsClient()
/// let patent = try await client.fetchPatent("CN122072823A")
/// print(patent.title)
/// ```
public actor GooglePatentsClient {
    private let session: URLSession
    private let baseURL: String = "https://patents.google.com"

    private static let userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// 获取专利完整信息
    public func fetchPatent(_ number: String) async throws -> PatentInfo {
        guard !number.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PatentClientError.invalidPatentNumber("专利号不能为空")
        }
        let url: String = patentURL(number)
        let html: String = try await fetchHTML(url)
        return try parsePatentHTML(html, patentNumber: number, url: url)
    }

    /// 下载专利 PDF
    public func downloadPDF(_ number: String, to destURL: URL) async throws {
        let info: PatentInfo = try await fetchPatent(number)
        guard !info.pdfUrl.isEmpty else {
            throw PatentClientError.notFound("无法找到 \(number) 的 PDF 链接")
        }
        try await downloadFile(info.pdfUrl, to: destURL)
    }

    // MARK: - URL 构建

    private func patentURL(_ number: String) -> String {
        "\(baseURL)/patent/\(number)/en"
    }

    // MARK: - HTTP

    private func fetchHTML(_ urlString: String) async throws -> String {
        guard let url: URL = URL(string: urlString) else {
            throw PatentClientError.invalidPatentNumber("无效 URL: \(urlString)")
        }
        var request: URLRequest = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9,zh-CN;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, response): (Data, URLResponse) = try await session.data(for: request)
        guard let httpResponse: HTTPURLResponse = response as? HTTPURLResponse else {
            throw PatentClientError.networkError("无效响应")
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw PatentClientError.notFound("专利 \(urlString) 未找到")
            }
            throw PatentClientError.networkError("HTTP \(httpResponse.statusCode)")
        }
        guard let html: String = String(data: data, encoding: .utf8) else {
            throw PatentClientError.parseError("无法解码 HTML")
        }
        return html
    }

    private func downloadFile(_ urlString: String, to destURL: URL) async throws {
        guard let url: URL = URL(string: urlString) else {
            throw PatentClientError.invalidPatentNumber("无效 PDF URL: \(urlString)")
        }
        var request: URLRequest = URLRequest(url: url, timeoutInterval: 60)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/pdf,application/octet-stream,*/*", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse) = try await session.data(for: request)
        guard let httpResponse: HTTPURLResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PatentClientError.networkError("PDF 下载失败")
        }
        try data.write(to: destURL, options: .atomic)
    }

    // MARK: - HTML 解析（对齐 XiaoNuo parsePatentFull）

    private func parsePatentHTML(_ html: String, patentNumber: String, url: String) throws -> PatentInfo {
        let doc: Document = try SwiftSoup.parse(html)

        // Title: meta DC.title → span[itemprop='title'] → h1
        let title: String = try firstNonEmpty(
            { try doc.select("meta[name='DC.title']").first()?.attr("content") ?? "" },
            { try doc.select("span[itemprop='title']").first()?.text() ?? "" },
            { try doc.select("h1").first()?.text() ?? "" }
        )

        // Inventors: dd[itemprop='inventor']
        let inventors: [String] = try doc.select("dd[itemprop='inventor']").map {
            try $0.text().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Assignees
        let assigneeOriginal: [String] = try doc.select("dd[itemprop='assigneeOriginal']").map {
            try $0.text().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let assigneeCurrent: [String] = try doc.select("dd[itemprop='assigneeCurrent']").map {
            try $0.text().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let assignee: String = assigneeCurrent.first ?? assigneeOriginal.first ?? "Unknown Assignee"

        // Abstract: meta DC.description → div[itemprop='abstract']
        let abstract: String = try firstNonEmpty(
            { try doc.select("meta[name='DC.description']").first()?.attr("content") ?? "" },
            { try doc.select("div[itemprop='abstract']").first()?.text() ?? "" }
        )

        // Dates: dd[itemprop='events'] 内的 span[itemprop='type'] + time[itemprop='date']
        let events: PatentEvents = try extractEvents(doc)

        // Legal status: dd[itemprop='legalStatusIfi']
        let legal: LegalStatusResult = try extractLegalStatus(doc)

        // PDF URL: meta[name='citation_pdf_url'] → a[href*='pdf']
        let pdfUrl: String = try extractPdfUrl(doc, patentNumber: patentNumber)

        // Classifications: dd[itemprop='classifications']
        let classifications: [String] = try doc.select("dd[itemprop='classifications']").map {
            try $0.text().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Citations
        let forwardCitations: [Citation] = try extractCitations(
            doc, selectors: ["tr[itemprop='forwardReferencesOrig']", "tr[itemprop='forwardReferencesFamily']"])
        let backwardCitations: [Citation] = try extractCitations(
            doc, selectors: ["tr[itemprop='backwardReferences']", "tr[itemprop='backwardReferencesFamily']"])

        return PatentInfo(
            patentNumber: patentNumber,
            title: title,
            inventors: inventors,
            assignee: assignee,
            assigneeOriginal: assigneeOriginal,
            assigneeCurrent: assigneeCurrent,
            publicationDate: events.pubDate,
            abstract: abstract,
            url: url,
            filingDate: events.filingDate,
            priorityDate: events.priorityDate,
            grantDate: events.grantDate,
            expirationDate: events.expirationDate,
            legalStatus: legal.status,
            ifiStatus: legal.ifiStatus,
            estimatedExpiration: legal.estimatedExpiration,
            pdfUrl: pdfUrl,
            classifications: classifications,
            forwardCitations: forwardCitations,
            backwardCitations: backwardCitations
        )
    }

    // MARK: - 事件（日期）提取

    private struct PatentEvents {
        var priorityDate: String = ""
        var filingDate: String = ""
        var grantDate: String = ""
        var expirationDate: String = ""
        var pubDate: String = ""
    }

    private func extractEvents(_ doc: Document) throws -> PatentEvents {
        var events: PatentEvents = PatentEvents()
        let eventElements = try doc.select("dd[itemprop='events']")
        for element in eventElements {
            let typeSpan = try element.select("span[itemprop='type']").first()
            let timeTag = try element.select("time[itemprop='date']").first()
            guard let typeText = try typeSpan?.text().trimmingCharacters(in: .whitespacesAndNewlines),
                let dateText = try timeTag?.text().trimmingCharacters(in: .whitespacesAndNewlines)
            else { continue }

            switch typeText {
            case "priority":
                events.priorityDate = dateText
            case "filed":
                events.filingDate = dateText
            case "granted":
                events.grantDate = dateText
            case "publication" where events.pubDate.isEmpty:
                events.pubDate = dateText
            default:
                break
            }

            // 检查是否有 expiration 标题
            let titleSpan = try element.select("span[itemprop='title']").first()
            if let titleText = try titleSpan?.text().lowercased(), titleText.contains("expiration") {
                events.expirationDate = dateText
            }
        }
        return events
    }

    // MARK: - 法律状态提取

    private struct LegalStatusResult {
        var status: String = ""
        var ifiStatus: String = ""
        var estimatedExpiration: String = ""
    }

    private func extractLegalStatus(_ doc: Document) throws -> LegalStatusResult {
        var result: LegalStatusResult = LegalStatusResult()

        // IFI 法律状态
        if let ifiElem: Element = try doc.select("dd[itemprop='legalStatusIfi']").first() {
            let text: String = try ifiElem.text().trimmingCharacters(in: .whitespacesAndNewlines)
            result.ifiStatus = text
            let parts: [Substring] = text.split(separator: ",")
            if let first: Substring = parts.first {
                result.status = String(first).trimmingCharacters(in: .whitespaces)
            }
            if let expMatch = text.range(
                of: #"expires?\s*(\d{4}-\d{2}-\d{2})"#, options: [.regularExpression, .caseInsensitive]) {
                result.estimatedExpiration = String(text[expMatch]).replacingOccurrences(
                    of: #"expires?\s*"#, with: "", options: [.regularExpression, .caseInsensitive]
                ).trimmingCharacters(in: .whitespaces)
            }
        }

        // legal-status 事件
        let eventElems = try doc.select("dd[itemprop='events']")
        for element in eventElems {
            let typeSpan = try element.select("span[itemprop='type']").first()
            guard try typeSpan?.text().trimmingCharacters(in: .whitespacesAndNewlines) == "legal-status" else {
                continue
            }
            let timeTag = try element.select("time[itemprop='date']").first()
            let dateText = try timeTag?.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if dateText == "Status" {
                let titleSpan = try element.select("span[itemprop='title']").first()
                if let title = try titleSpan?.text().trimmingCharacters(in: .whitespacesAndNewlines) {
                    result.status = title.replacingOccurrences(of: "Current", with: "").trimmingCharacters(
                        in: .whitespaces)
                }
            } else if let dateText = dateText, dateText.first?.isNumber == true {
                result.estimatedExpiration = dateText
            }
        }

        return result
    }

    // MARK: - PDF URL 提取

    private func extractPdfUrl(_ doc: Document, patentNumber: String) throws -> String {
        // 优先 meta 标签
        if let meta = try doc.select("meta[name='citation_pdf_url']").first(),
            let href = try? meta.attr("content"), !href.isEmpty {
            return href
        }
        // 回退：a[href*='pdf'] + download
        let links = try doc.select("a[href]")
        for link in links {
            let href: String = (try? link.attr("href").lowercased()) ?? ""
            let text: String = (try? link.text().lowercased()) ?? ""
            if href.contains("download") || text.contains("download"), href.contains("pdf") {
                var url = try link.attr("href")
                if url.hasPrefix("/") {
                    url = "https://patents.google.com\(url)"
                } else if !url.hasPrefix("http") {
                    url = "https://patents.google.com/\(url)"
                }
                return url
            }
        }
        return "https://patents.google.com/patent/\(patentNumber)/en/download"
    }

    // MARK: - 引证提取

    private func extractCitations(_ doc: Document, selectors: [String]) throws -> [Citation] {
        var citations: [Citation] = []
        for selector in selectors {
            let rows = try doc.select(selector)
            for row in rows {
                let pubNum: String =
                    (try? row.select("span[itemprop='publicationNumber']").first()?.text().trimmingCharacters(
                        in: .whitespacesAndNewlines)) ?? ""
                let priDate: String =
                    (try? row.select("td[itemprop='priorityDate']").first()?.text().trimmingCharacters(
                        in: .whitespacesAndNewlines)) ?? ""
                let pubDate: String =
                    (try? row.select("td[itemprop='publicationDate']").first()?.text().trimmingCharacters(
                        in: .whitespacesAndNewlines)) ?? ""
                if !pubNum.isEmpty {
                    citations.append(Citation(patentNumber: pubNum, priorityDate: priDate, pubDate: pubDate))
                }
            }
        }
        return citations
    }

    // MARK: - 辅助

    /// 返回第一个非空字符串
    private func firstNonEmpty(_ extractors: (() throws -> String)...) throws -> String {
        for extractor in extractors {
            let value = try extractor()
            if !value.isEmpty { return value }
        }
        return "Unknown Title"
    }
}
