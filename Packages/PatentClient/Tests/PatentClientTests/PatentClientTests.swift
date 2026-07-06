import Foundation
import Testing

@testable import PatentClient

struct PatentClientTests {

    // MARK: - GooglePatentsClient

    @Test func googlePatentsClientInit() {
        _ = GooglePatentsClient()
    }

    @Test func googlePatentsClient_invalidPatentNumber_throws() async {
        let client = GooglePatentsClient()
        await #expect(throws: PatentClientError.invalidPatentNumber("专利号不能为空")) {
            try await client.fetchPatent("")
        }
    }

    // MARK: - PssClient

    @Test func pssClientInit() {
        _ = PssClient()
    }

    @Test func pssClient_sessionManagement() async {
        let client = PssClient()
        var valid = await client.hasValidSession()
        #expect(!valid)

        let session = PssSession(cookies: ["token": "abc"], createdAt: Date())
        await client.setSession(session)
        valid = await client.hasValidSession()
        #expect(valid)

        await client.clearSession()
        valid = await client.hasValidSession()
        #expect(!valid)
    }

    @Test func pssClient_sessionExpiry() {
        let expired = PssSession(
            cookies: ["token": "abc"],
            createdAt: Date().addingTimeInterval(-3600)
        )
        #expect(!expired.isValid)

        let fresh = PssSession(cookies: ["token": "abc"], createdAt: Date())
        #expect(fresh.isValid)
    }

    @Test func pssClient_saveLoadSession() async throws {
        let client = PssClient()
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pss-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let session = PssSession(cookies: ["JSESSIONID": "xyz"], createdAt: Date())
        await client.setSession(session)
        try await client.saveSession(to: tmpURL)

        let client2 = PssClient()
        try await client2.loadSession(from: tmpURL)
        let valid = await client2.hasValidSession()
        #expect(valid)
    }

    // MARK: - Types

    @Test func patentInfoInit() {
        let info = PatentInfo(patentNumber: "CN123456789A")
        #expect(info.patentNumber == "CN123456789A")
        #expect(info.title.isEmpty)
        #expect(info.inventors.isEmpty)
        #expect(info.forwardCitations.isEmpty)
    }

    @Test func citationInit() {
        let c = Citation(patentNumber: "US9876543B2", priorityDate: "2020-01-01")
        #expect(c.patentNumber == "US9876543B2")
        #expect(c.priorityDate == "2020-01-01")
    }

    @Test func pssSearchResultInit() {
        let brief = PssPatentBrief(pubNumber: "CN123A", title: "测试专利")
        let result = PssSearchResult(keyword: "测试", totalHits: 1, patents: [brief])
        #expect(result.keyword == "测试")
        #expect(result.patents.count == 1)
        #expect(result.patents[0].pubNumber == "CN123A")
    }

    @Test func pssPatentDetailInit() {
        let detail = PssPatentDetail(pubNumber: "CN123A", title: "测试", abstract: "摘要")
        #expect(detail.pubNumber == "CN123A")
        #expect(detail.imageURL == nil)
    }

    @Test func patentClientErrorDescriptions() {
        #expect(PatentClientError.networkError("timeout").errorDescription == "网络错误: timeout")
        #expect(PatentClientError.parseError("bad html").errorDescription == "解析错误: bad html")
        #expect(PatentClientError.notFound("CN999").errorDescription == "未找到: CN999")
        #expect(PatentClientError.unauthorized("no cookie").errorDescription == "未授权: no cookie")
        #expect(
            PatentClientError.invalidPatentNumber("bad").errorDescription == "无效专利号: bad")
    }

    @Test func patentInfoCodable() throws {
        let info = PatentInfo(
            patentNumber: "CN123A",
            title: "发明",
            inventors: ["张三"],
            classifications: ["G06F"]
        )
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(PatentInfo.self, from: data)
        #expect(decoded.patentNumber == "CN123A")
        #expect(decoded.inventors == ["张三"])
    }

    @Test func pssPatentBriefCodable() throws {
        let brief = PssPatentBrief(pubNumber: "CN123A", title: "测试", ipc: "G06F")
        let data = try JSONEncoder().encode(brief)
        let decoded = try JSONDecoder().decode(PssPatentBrief.self, from: data)
        #expect(decoded.pubNumber == "CN123A")
        #expect(decoded.ipc == "G06F")
    }

    @Test func pssSessionCodable() throws {
        let session = PssSession(cookies: ["a": "1"], createdAt: Date())
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(PssSession.self, from: data)
        #expect(decoded.cookies["a"] == "1")
    }

    @Test func pssClientDefaultSessionURL() {
        let url = PssClient.defaultSessionURL()
        #expect(url.lastPathComponent == "pss-cookies.json")
        #expect(url.path.contains(".config/yunpat"))
    }
}
