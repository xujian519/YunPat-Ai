import Foundation

/// 检索源标识
public enum SearchSource: String, Sendable {
    case cnipa
    case googlePatents
    case espacenet
    case wipo
    case semanticScholar
    case localKB  // 本地知识库
}

public struct SearchResult: Sendable {
    public let source: SearchSource
    public let patentNumber: String
    public let title: String
    public let relevanceScore: Double
    public let metadata: [String: String]

    public init(
        source: SearchSource, patentNumber: String, title: String, relevanceScore: Double = 0,
        metadata: [String: String] = [:]
    ) {
        self.source = source
        self.patentNumber = patentNumber
        self.title = title
        self.relevanceScore = relevanceScore
        self.metadata = metadata
    }
}

/// 多源检索协调器 — 本地知识库 + 外部检索（真实 HTTP + URL 生成回退）
public actor SearchCommander {
    private let wikiAdapter: WikiAdapter
    private var remoteSearchHandler: (@Sendable (String, SearchSource) async -> [SearchResult])?

    public init(wikiAdapter: WikiAdapter) { self.wikiAdapter = wikiAdapter }

    /// 注入远程检索处理器 — App 层可用 PatentClient 接入真实 HTTP 检索
    public func configureRemoteSearch(
        _ handler: @Sendable @escaping (String, SearchSource) async -> [SearchResult]
    ) {
        remoteSearchHandler = handler
    }

    /// 按优先级从多个源检索并合并
    public func search(
        query: String,
        sources: [SearchSource] = [.localKB, .googlePatents, .cnipa]
    ) async -> [SearchResult] {
        var results: [SearchResult] = []

        for source in sources {
            let sourceResults: [SearchResult] = await searchSource(source, query: query)
            results.append(contentsOf: sourceResults)
        }

        return mergeAndRank(results)
    }

    // MARK: - Source Dispatch

    private func searchSource(_ source: SearchSource, query: String) async -> [SearchResult] {
        if let handler = remoteSearchHandler {
            let remoteResults: [SearchResult] = await handler(query, source)
            if !remoteResults.isEmpty { return remoteResults }
        }

        switch source {
        case .localKB:
            return await searchLocalKB(query: query)
        case .googlePatents:
            let httpResults: [SearchResult] = await searchGooglePatentsHTTP(query: query)
            return httpResults.isEmpty ? buildGooglePatentsResults(query: query) : httpResults
        case .cnipa:
            return buildCNIPAResults(query: query)
        case .espacenet:
            return buildEspacenetResults(query: query)
        case .wipo:
            return buildWIOResults(query: query)
        case .semanticScholar:
            return buildScholarResults(query: query)
        }
    }

    // MARK: - Local KB

    private func searchLocalKB(query: String) async -> [SearchResult] {
        guard let facts: String = try? await wikiAdapter.readModuleIndex(.patentPractice) else {
            return []
        }
        if facts.lowercased().contains(query.lowercased()) {
            return [
                SearchResult(
                    source: .localKB,
                    patentNumber: "KB",
                    title: query,
                    relevanceScore: 0.8
                )
            ]
        }
        return []
    }

    // MARK: - Google Patents HTTP (XHR API)

    /// 通过 Google Patents XHR API 执行真实检索
    private func searchGooglePatentsHTTP(query: String) async -> [SearchResult] {
        let patentNumbers: [String] = extractPatentNumbers(from: query)
        if !patentNumbers.isEmpty {
            return patentNumbers.map { patentNum in
                SearchResult(
                    source: .googlePatents,
                    patentNumber: patentNum,
                    title: "Google Patents: \(patentNum)",
                    relevanceScore: 1.0,
                    metadata: [
                        "url": "https://patents.google.com/patent/\(patentNum)/en",
                        "type": "direct"
                    ]
                )
            }
        }

        let encodedQuery: String = encodeQuery(query)
        let apiURLString: String =
            "https://patents.google.com/xhr/query?url=q%3D\(encodedQuery)%26num%3D10&exp="
        guard let url: URL = URL(string: apiURLString) else { return [] }

        var request: URLRequest = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://patents.google.com", forHTTPHeaderField: "Origin")

        do {
            let (data, response): (Data, URLResponse) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return parseGooglePatentsXHR(data: data)
        } catch {
            print("[SearchCommander] Google Patents HTTP failed: \(error.localizedDescription)")
            return []
        }
    }

    /// 解析 Google Patents XHR JSON 响应，提取专利号、标题和摘要
    private func parseGooglePatentsXHR(data: Data) -> [SearchResult] {
        guard let json: Any = try? JSONSerialization.jsonObject(with: data),
              let root = json as? [String: Any],
              let cluster = root["results_cluster"] as? [String: Any] else { return [] }

        var results: [SearchResult] = []

        if let resultsArray = cluster["result"] as? [[String: Any]] {
            for (idx, item) in resultsArray.prefix(10).enumerated() {
                guard let patent = item["patent"] as? [String: Any] else { continue }
                let publicationNumber: String = (patent["publication_number"] as? String) ?? "unknown"
                let title: String = (patent["title"] as? [String: Any])?["en"] as? String
                    ?? (patent["snippet"] as? String)?.prefix(80).description
                    ?? publicationNumber
                let snippet: String = (patent["snippet"] as? String) ?? ""

                results.append(
                    SearchResult(
                        source: .googlePatents,
                        patentNumber: publicationNumber,
                        title: title,
                        relevanceScore: max(0.9 - Double(idx) * 0.08, 0.3),
                        metadata: [
                            "url": "https://patents.google.com/patent/\(publicationNumber)/en",
                            "snippet": String(snippet.prefix(200)),
                            "type": "remote"
                        ]
                    )
                )
            }
        }

        return results
    }

    // MARK: - Google Patents URL Builder

    /// 构建 Google Patents 检索结果 — 通过 URL 编码构造检索链接
    private func buildGooglePatentsResults(query: String) -> [SearchResult] {
        let encodedQuery: String = encodeQuery(query)
        let searchURL: String = "https://patents.google.com/?q=\(encodedQuery)&num=10"

        // 如果查询包含专利号，构造直接链接
        let patentNumbers: [String] = extractPatentNumbers(from: query)
        var results: [SearchResult] = patentNumbers.map { patentNum in
            SearchResult(
                source: .googlePatents,
                patentNumber: patentNum,
                title: "Google Patents: \(patentNum)",
                relevanceScore: 1.0,
                metadata: [
                    "url": "https://patents.google.com/patent/\(patentNum)/en",
                    "type": "direct"
                ]
            )
        }

        results.append(
            SearchResult(
                source: .googlePatents,
                patentNumber: "GP-SEARCH",
                title: "Google Patents 检索: \(query.prefix(80))",
                relevanceScore: 0.6,
                metadata: [
                    "url": searchURL,
                    "type": "search"
                ]
            )
        )

        return results
    }

    // MARK: - CNIPA URL Builder

    private func buildCNIPAResults(query: String) -> [SearchResult] {
        let encodedQuery: String = encodeQuery(query)
        let patentNumbers: [String] = extractPatentNumbers(from: query)
        var results: [SearchResult] = patentNumbers.map { patentNum in
            SearchResult(
                source: .cnipa,
                patentNumber: patentNum,
                title: "CNIPA 公布公告: \(patentNum)",
                relevanceScore: 1.0,
                metadata: [
                    "url": "http://epub.cnipa.gov.cn/patentoutline.search/" +
                        "?queryValue=\(encodedQuery)&searchType=pub",
                    "type": "direct"
                ]
            )
        }

        results.append(
            SearchResult(
                source: .cnipa,
                patentNumber: "CNIPA-SEARCH",
                title: "CNIPA 检索: \(query.prefix(80))",
                relevanceScore: 0.5,
                metadata: [
                    "url": "http://epub.cnipa.gov.cn/patentoutline.search/" +
                        "?queryValue=\(encodedQuery)&searchType=pub",
                    "type": "search"
                ]
            )
        )

        return results
    }

    // MARK: - Espacenet URL Builder

    private func buildEspacenetResults(query: String) -> [SearchResult] {
        let encodedQuery: String = encodeQuery(query)
        let searchURL: String = "https://worldwide.espacenet.com/searchResults?" +
            "ST=singleline&locale=en_EP&submitted=true&DB=&query=\(encodedQuery)"

        return [
            SearchResult(
                source: .espacenet,
                patentNumber: "EP-SEARCH",
                title: "Espacenet 检索: \(query.prefix(80))",
                relevanceScore: 0.5,
                metadata: [
                    "url": searchURL,
                    "type": "search"
                ]
            )
        ]
    }

    // MARK: - WIPO URL Builder

    private func buildWIOResults(query: String) -> [SearchResult] {
        let encodedQuery: String = encodeQuery(query)
        let searchURL: String = "https://patentscope.wipo.int/search/zh/result.jsf?" +
            "query=\(encodedQuery)&currentNavigationRow=1"

        return [
            SearchResult(
                source: .wipo,
                patentNumber: "WIPO-SEARCH",
                title: "WIPO Patentscope 检索: \(query.prefix(80))",
                relevanceScore: 0.5,
                metadata: [
                    "url": searchURL,
                    "type": "search"
                ]
            )
        ]
    }

    // MARK: - Semantic Scholar URL Builder

    private func buildScholarResults(query: String) -> [SearchResult] {
        let encodedQuery: String = encodeQuery(query)
        let searchURL: String = "https://www.semanticscholar.org/search?q=" +
            "\(encodedQuery)&sort=relevance"

        return [
            SearchResult(
                source: .semanticScholar,
                patentNumber: "SCHOLAR-SEARCH",
                title: "Semantic Scholar 检索: \(query.prefix(80))",
                relevanceScore: 0.4,
                metadata: [
                    "url": searchURL,
                    "type": "academic"
                ]
            )
        ]
    }

    // MARK: - Utilities

    private func encodeQuery(_ query: String) -> String {
        query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    }
}

// MARK: - Pure Helpers

extension SearchCommander {

    /// 从查询文本中提取专利号（支持 CN/US/EP/WO + 数字格式）
    private func extractPatentNumbers(from text: String) -> [String] {
        let pattern: String = #"\b(CN|US|EP|WO|JP|KR|DE|FR|GB)\d{6,}[A-Z]?\b"#
        guard let regex: NSRegularExpression = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ) else { return [] }

        let range: NSRange = NSRange(text.startIndex..., in: text)
        let matches: [NSTextCheckingResult] = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { match in
            guard let range: Range<String.Index> = Range(match.range, in: text) else {
                return nil
            }
            return String(text[range]).uppercased()
        }
    }

    private func mergeAndRank(_ results: [SearchResult]) -> [SearchResult] {
        var seen: Set<String> = []
        return results.sorted { $0.relevanceScore > $1.relevanceScore }.filter {
            seen.insert($0.patentNumber).inserted
        }
    }
}
