import Foundation
import Testing

@testable import YunPatNetworking

struct PrivacyFilterTests {

    let filter: PrivacyFilter = PrivacyFilter.shared

    // MARK: - 本地 provider 不脱敏

    @Test func localProviderSkipsScrub() async {
        let result: ScrubResult = await filter.scrub(
            text: "my email is test@example.com",
            provider: .ollama,
            caseId: nil
        )
        #expect(result.detections.isEmpty)
        #expect(result.scrubbedText == "my email is test@example.com")
    }

    // MARK: - 邮箱脱敏

    @Test func scrubsEmail() async {
        let result: ScrubResult = await filter.scrub(
            text: "contact me at alice@example.com please",
            provider: .deepseek,
            caseId: nil
        )
        #expect(!result.detections.isEmpty)
        let emailDets: [Detection] = result.detections.filter { $0.kind == .email }
        #expect(!emailDets.isEmpty)
        #expect(emailDets[0].entity == "alice@example.com")
        // 占位符不应是原文
        #expect(!result.scrubbedText.contains("alice@example.com"))
        #expect(result.scrubbedText.contains("[EMAIL_"))
    }

    // MARK: - 手机号脱敏

    @Test func scrubsPhone() async {
        let result: ScrubResult = await filter.scrub(
            text: "phone: 13800138000",
            provider: .deepseek,
            caseId: nil
        )
        let phoneDets: [Detection] = result.detections.filter { $0.kind == .phone }
        #expect(!phoneDets.isEmpty)
        #expect(!result.scrubbedText.contains("13800138000"))
    }

    // 全相同数字不应被视为有效手机号
    @Test func ignoresAllSameDigitPhone() async {
        let result: ScrubResult = await filter.scrub(
            text: "11111111111 is not a real phone",
            provider: .deepseek,
            caseId: nil
        )
        let phoneDets: [Detection] = result.detections.filter { $0.kind == .phone }
        #expect(phoneDets.isEmpty)
    }

    // MARK: - 身份证脱敏

    @Test func scrubsIdNumber() async {
        let result: ScrubResult = await filter.scrub(
            text: "id: 110101199001011234",
            provider: .deepseek,
            caseId: nil
        )
        let idDets: [Detection] = result.detections.filter { $0.kind == .idNumber }
        #expect(!idDets.isEmpty)
        #expect(!result.scrubbedText.contains("110101199001011234"))
    }

    // MARK: - 多模式同时存在

    @Test func scrubsMultiplePatterns() async {
        let text: String = """
            email: bob@company.cn
            phone: 13912345678
            """
        let result: ScrubResult = await filter.scrub(text: text, provider: .anthropic, caseId: nil)
        #expect(result.detections.count >= 2)
        #expect(!result.scrubbedText.contains("bob@company.cn"))
        #expect(!result.scrubbedText.contains("13912345678"))
    }

    // MARK: - placeholderMap 可恢复

    @Test func placeholderMapRestoresOriginal() async {
        let original: String = "email: alice@example.com"
        let result: ScrubResult = await filter.scrub(text: original, provider: .deepseek, caseId: nil)
        var restored: String = result.scrubbedText
        for (placeholder, originalVal) in result.placeholderMap {
            restored = restored.replacingOccurrences(of: placeholder, with: originalVal)
        }
        #expect(restored == original)
    }

    // MARK: - ChatRequest 级别的脱敏

    @Test func scrubsChatRequest() async throws {
        let req: ChatRequest = ChatRequest(
            model: "deepseek-chat",
            messages: [
                Message(role: .user, content: "my email is alice@example.com"),
                Message(role: .assistant, content: "I see your email")
            ],
            systemPrompt: "System with phone 13800138000"
        )
        let (scrubbed, result): (ChatRequest, ScrubResult) = try await filter.scrub(
            request: req, provider: .deepseek, caseId: nil)
        // messages 被脱敏
        for msg in scrubbed.messages {
            #expect(!msg.content.contains("alice@example.com"))
        }
        // systemPrompt 被脱敏
        if let systemPrompt = scrubbed.systemPrompt {
            #expect(!systemPrompt.contains("13800138000"))
        }
        #expect(!result.detections.isEmpty)
        #expect(!result.placeholderMap.isEmpty)
    }

    // MARK: - 客户自定义敏感词

    @Test func scrubsCustomTerms() async {
        let registry: SensitiveTermsRegistry = SensitiveTermsRegistry.shared
        await registry.reset()
        await registry.register(value: "华为技术有限公司", kind: .applicantName, scope: .firmLevel)

        let result: ScrubResult = await filter.scrub(
            text: "本案申请人华为技术有限公司提出申请",
            provider: .deepseek,
            caseId: nil
        )
        let customDets: [Detection] = result.detections.filter { $0.kind == .applicantName }
        #expect(!customDets.isEmpty)
        #expect(!result.scrubbedText.contains("华为技术有限公司"))
    }
}
