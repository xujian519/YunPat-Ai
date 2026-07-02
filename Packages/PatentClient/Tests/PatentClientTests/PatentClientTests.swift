import Testing

@testable import PatentClient

struct PatentClientTests {
    @Test func googlePatentsClientExists() {
        // 验证客户端可初始化
        let client = GooglePatentsClient()
        #expect(client is GooglePatentsClient)
    }

    @Test func pssClientExists() {
        let client = PssClient()
        #expect(client is PssClient)
    }
}
