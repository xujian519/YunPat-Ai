import Foundation
import SwiftSoup

// MARK: - PSS 客户端

/// PSS（中国专利审查信息查询系统）HTTP 客户端。
///
/// 不自带浏览器登录 — 需外部注入 Cookie 会话（从浏览器导出或 Peekaboo 获取）。
///
/// ```swift
/// let client = PSSClient()
/// let cookies = ["JSESSIONID": "abc123", "token": "xyz789"]
/// client.setSession(PssSession(cookies: cookies))
/// let results = try await client.search(keyword: "人工智能")
/// ```
public actor PssClient {
    private let session: URLSession
    private let baseURL: String
    private var currentSession: PssSession?

    private static let userAgent: String = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "AppleWebKit/537.36 (KHTML, like Gecko)",
        "Chrome/120.0.0.0 Safari/537.36"
    ].joined(separator: " ")

    public init(baseURL: String = "https://pss-system.cponline.cnipa.gov.cn", session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - 会话管理（外部注入）

    /// 注入外部获取的 Cookie 会话
    public func setSession(_ pssSession: PssSession) {
        currentSession = pssSession
    }

    /// 清除当前会话
    public func clearSession() {
        currentSession = nil
    }

    /// 检查当前会话是否有效
    public func hasValidSession() -> Bool {
        currentSession?.isValid ?? false
    }

    /// 持久化会话到文件
    public func saveSession(to url: URL) async throws {
        guard let session = currentSession else {
            throw PatentClientError.unauthorized("无活动会话")
        }
        let data: Data = try JSONEncoder().encode(session)
        try data.write(to: url, options: .atomic)
    }

    /// 从文件恢复会话
    public func loadSession(from url: URL) async throws {
        let data: Data = try Data(contentsOf: url)
        let pssSession: PssSession = try JSONDecoder().decode(PssSession.self, from: data)
        setSession(pssSession)
    }

    /// 默认会话文件路径
    public static func defaultSessionURL() -> URL {
        let configDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/yunpat", isDirectory: true)
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        return configDir.appendingPathComponent("pss-cookies.json")
    }

    // MARK: - Public API

    /// 搜索中国专利
    public func search(keyword: String, page: Int = 0, pageSize: Int = 20) async throws -> PssSearchResult {
        let cookies: [String: String] = try requireSession().cookies
        let cookieHeader: String = buildCookieHeader(cookies)
        let token: String = cookies["token"] ?? ""

        // PSS 搜索：POST 表单
        let searchURL: String = "\(baseURL)/search"
        let encodedKeyword: String = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let body: String = "keyword=\(encodedKeyword)&page=\(page)&pageSize=\(pageSize)"

        let html: String = try await httpPost(
            searchURL, body: body, contentType: "application/x-www-form-urlencoded",
            cookieHeader: cookieHeader, token: token)
        return try parseSearchResults(html, keyword: keyword)
    }

    /// 查询专利详情
    public func detail(pubNumber: String) async throws -> PssPatentDetail {
        let cookies: [String: String] = try requireSession().cookies
        let cookieHeader: String = buildCookieHeader(cookies)
        let token: String = cookies["token"] ?? ""

        let detailURL: String = "\(baseURL)/detail/\(pubNumber)"
        let html: String = try await httpGet(detailURL, cookieHeader: cookieHeader, token: token)
        return try parseDetail(html, pubNumber: pubNumber)
    }

    // MARK: - 内部 HTTP

    private func httpGet(_ urlString: String, cookieHeader: String, token: String) async throws -> String {
        guard let url: URL = URL(string: urlString) else {
            throw PatentClientError.invalidPatentNumber("无效 URL: \(urlString)")
        }
        var request: URLRequest = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("zh-CN,en-US;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PatentClientError.networkError("无效响应")
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw PatentClientError.unauthorized("PSS 会话已过期，请重新登录")
        }
        guard httpResponse.statusCode == 200 else {
            throw PatentClientError.networkError("HTTP \(httpResponse.statusCode)")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw PatentClientError.parseError("无法解码 HTML")
        }
        return html
    }

    private func httpPost(
        _ urlString: String, body: String, contentType: String,
        cookieHeader: String, token: String
    ) async throws -> String {
        guard let url: URL = URL(string: urlString) else {
            throw PatentClientError.invalidPatentNumber("无效 URL: \(urlString)")
        }
        var request: URLRequest = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("zh-CN,en-US;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PatentClientError.networkError("无效响应")
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw PatentClientError.unauthorized("PSS 会话已过期，请重新登录")
        }
        guard httpResponse.statusCode == 200 else {
            throw PatentClientError.networkError("HTTP \(httpResponse.statusCode)")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw PatentClientError.parseError("无法解码 HTML")
        }
        return html
    }

    // MARK: - Cookie 辅助

    private func buildCookieHeader(_ cookies: [String: String]) -> String {
        cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    private func requireSession() throws -> PssSession {
        guard let session = currentSession, session.isValid else {
            throw PatentClientError.unauthorized("无有效 PSS 会话。请先用 setSession() 注入 Cookie 或 loadSession() 恢复")
        }
        return session
    }

    // MARK: - HTML 解析

    /// 解析搜索结果表格
    private func parseSearchResults(_ html: String, keyword: String) throws -> PssSearchResult {
        let doc: Document = try SwiftSoup.parse(html)
        var patents: [PssPatentBrief] = []

        // 查找搜索结果表格行
        let rows: Elements = try doc.select(
            "table.patent-table tbody tr, table.result-table tbody tr, .search-result tr")
        for row in rows {
            let cells: Elements = try row.select("td")
            guard cells.count >= 5 else { continue }
            let brief: PssPatentBrief = PssPatentBrief(
                pubNumber: (try? cells[0].text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "",
                title: (try? cells[1].text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "",
                applicant: (try? cells[2].text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "",
                appNumber: (try? cells[3].text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "",
                appDate: (try? cells[4].text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "",
                pubDate: cells.count > 5
                    ? ((try? cells[5].text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "")
                    : "",
                status: cells.count > 6
                    ? ((try? cells[6].text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "")
                    : "",
                ipc: cells.count > 7
                    ? ((try? cells[7].text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "")
                    : ""
            )
            patents.append(brief)
        }

        // 回退：从页面统计信息提取 totalHits
        var totalHits: Int = patents.count
        if let totalText: String = try doc.select("*:containsOwn(共), *:containsOwn(总计)").first()?.text() {
            if let match: Range<String.Index> = totalText.range(of: #"\d+"#, options: .regularExpression) {
                totalHits = Int(totalText[match]) ?? totalHits
            }
        }

        return PssSearchResult(keyword: keyword, totalHits: totalHits, patents: patents)
    }

    /// 解析详情页
    private func parseDetail(_ html: String, pubNumber: String) throws -> PssPatentDetail {
        let doc: Document = try SwiftSoup.parse(html)

        // 使用中文标签 + 相邻值提取
        func extractValue(for label: String, in doc: Document) throws -> String {
            // 模式: th:contains(label) → 下一个 td 或同级 dd
            if let headerCell: Element = try doc.select("th:contains(\(label))").first(),
                let dataCell: Element = try headerCell.parent()?.select("td").first() {
                return try dataCell.text().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let termElement: Element = try doc.select("dt:contains(\(label))").first(),
                let descElement: Element = try termElement.nextElementSibling() {
                return try descElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ""
        }

        return PssPatentDetail(
            pubNumber: pubNumber,
            title: try extractValue(for: "发明名称", in: doc),
            appNumber: try extractValue(for: "申请号", in: doc),
            appDate: try extractValue(for: "申请日", in: doc),
            pubDate: (try extractValue(for: "公开日", in: doc)).isEmpty
                ? (try extractValue(for: "公告日", in: doc))
                : (try extractValue(for: "公开日", in: doc)),
            applicant: try extractValue(for: "申请人", in: doc),
            inventor: try extractValue(for: "发明人", in: doc),
            ipc: try extractValue(for: "IPC", in: doc),
            cpc: try extractValue(for: "CPC", in: doc),
            priority: try extractValue(for: "优先权", in: doc),
            abstract: try extractValue(for: "摘要", in: doc),
            claims: try extractValue(for: "权利要求", in: doc),
            description: try extractValue(for: "说明书", in: doc),
            status: try extractValue(for: "法律状态", in: doc),
            agency: try extractValue(for: "代理机构", in: doc),
            agent: try extractValue(for: "代理人", in: doc),
            address: try extractValue(for: "地址", in: doc)
        )
    }
}
