import Foundation

/// 隐私相关类型的命名空间
public enum PrivacyTypes {}

// MARK: - Entity Kind

/// 敏感实体类型枚举 — email / phone / idNumber / bankCard / unifiedSocialCreditCode 等
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

/// 检测来源 — 正则匹配（regex）或自定义词表（customList）
public enum DetectionSource: String, Sendable, Codable {
    case regex
    case customList
}

// MARK: - Detection

/// 敏感信息检测结果 — 实体类型、原文、占位符、匹配范围和检测来源
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

/// 脱敏请求 — 待脱敏文本、模型提供商和案件上下文
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

/// 脱敏结果 — 脱敏后文本、检测列表、占位符映射和 fail-closed 阻断标记
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
