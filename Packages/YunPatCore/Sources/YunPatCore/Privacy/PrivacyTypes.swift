import Foundation
import YunPatNetworking

public enum PrivacyTypes {}  // namespace for privacy-related types

// MARK: - Entity Kind

public enum EntityKind: String, Sendable, Codable {
    case email
    case phone
    case idNumber  // 身份证号
    case bankCard  // 银行卡号
    case unifiedSocialCreditCode  // 统一社会信用代码
    case applicantName  // 申请人名称
    case inventorName  // 发明人名称
    case custom  // 自定义敏感词
}

public enum DetectionSource: String, Sendable, Codable {
    case regex
    case customList
}

// MARK: - Detection

public struct Detection: Sendable, Codable, Identifiable {
    public let id: UUID
    public let kind: EntityKind
    public let entity: String
    public let placeholder: String
    public let range: NSRange
    public let source: DetectionSource

    public init(
        kind: EntityKind, entity: String, placeholder: String,
        range: NSRange, source: DetectionSource
    ) {
        self.id = UUID()
        self.kind = kind
        self.entity = entity
        self.placeholder = placeholder
        self.range = range
        self.source = source
    }
}

// MARK: - Scrub Request / Result

public struct ScrubRequest: Sendable {
    public let text: String
    public let provider: ModelProvider
    public let caseId: String?

    public init(text: String, provider: ModelProvider, caseId: String? = nil) {
        self.text = text
        self.provider = provider
        self.caseId = caseId
    }
}

public struct ScrubResult: Sendable {
    public let scrubbedText: String
    public let detections: [Detection]
    public let placeholderMap: [String: String]  // placeholder → original
    public let blocked: Bool  // fail-closed: 脱敏后仍有泄漏

    public init(
        scrubbedText: String, detections: [Detection], placeholderMap: [String: String],
        blocked: Bool = false
    ) {
        self.scrubbedText = scrubbedText
        self.detections = detections
        self.placeholderMap = placeholderMap
        self.blocked = blocked
    }
}
