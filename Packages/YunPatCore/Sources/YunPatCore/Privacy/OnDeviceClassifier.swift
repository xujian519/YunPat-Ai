import Foundation

/// On-device PII 分类器 — 关键词匹配 + 上下文评分
///
/// 与 PrivacyFilter 的正则层互补：
/// - 正则层/捕捉固定模式（邮箱/电话/证件号）
/// - 分类器/捕捉上下文性 PII（人名/公司名/地址等自由文本）
///
/// 后期可接入 MLX 模型做真实序列分类。
public struct OnDeviceClassifier: Sendable {
    public static let shared: OnDeviceClassifier = OnDeviceClassifier()

    private struct PatternEntry: Sendable {
        let category: Category
        let pattern: String
        let confidence: Float
    }

    public enum Category: String, Sendable, CaseIterable {
        case personName
        case organization
        case address
        case financial
        case credential
        case technicalSecret
        case custom
    }

    public struct Result: Sendable {
        public let detections: [Detection]
        public let isSensitive: Bool
        public init(detections: [Detection]) {
            self.detections = detections
            self.isSensitive = !detections.isEmpty
        }
    }

    public struct Detection: Sendable {
        public let category: Category
        public let text: String
        public let confidence: Float
        public let range: NSRange
    }

    private let patterns: [PatternEntry] = [
        PatternEntry(category: .personName, pattern: "先生|女士|小姐|博士|教授|工程师|代理师|我叫|我是|姓名[：:]?", confidence: 0.6),
        PatternEntry(category: .personName, pattern: "[张王李赵陈刘杨黄吴周徐孙马胡朱郭何罗][某]?总", confidence: 0.5),
        PatternEntry(category: .personName, pattern: "(?:发明人|申请人)[：:?]?\\s*[\\u4e00-\\u9fa5]{2,4}", confidence: 0.7),
        PatternEntry(category: .organization, pattern: "(?:有限|责任)[公司]|股份有限公司|集团|事务所|大学|学院|研究院|中心", confidence: 0.4),
        PatternEntry(
            category: .organization,
            pattern: "(?:申请(?:人|权)?)[：:]?\\s*[\\u4e00-\\u9fa5]{4,20}(?:有限|责任)?公司?",
            confidence: 0.65
        ),
        PatternEntry(
            category: .organization,
            pattern: "委托(?:人|方)[：:]?\\s*[\\u4e00-\\u9fa5]{2,10}",
            confidence: 0.55
        ),
        PatternEntry(
            category: .address,
            pattern: "[\\u4e00-\\u9fa5]{2,}(?:省|市|区|县|镇|街道|路|街|巷|号|楼|层|室)",
            confidence: 0.45
        ),
        PatternEntry(category: .address, pattern: "地址[：:]?\\s*[\\u4e00-\\u9fa5\\d]{5,}", confidence: 0.6),
        PatternEntry(category: .financial, pattern: "开户[行账][：:]?\\s*\\S{4,}", confidence: 0.7),
        PatternEntry(category: .financial, pattern: "账号[：:]?\\s*\\d{8,}", confidence: 0.75),
        PatternEntry(category: .credential, pattern: "密码|令牌|token|secret|key|密钥|证书", confidence: 0.5),
        PatternEntry(
            category: .credential,
            pattern: "[Aa][Pp][Ii]_?[Kk]ey|sk-[a-zA-Z0-9]{20,}|ak-[a-zA-Z0-9]{20,}",
            confidence: 0.85
        ),
        PatternEntry(category: .technicalSecret, pattern: "核心技术|机密|商业秘密|专有技术|know-?how|技术诀窍", confidence: 0.5),
        PatternEntry(
            category: .technicalSecret,
            pattern: "未公开|未公布|尚未公开|保密",
            confidence: 0.45
        )
    ]

    private init() {}

    public func classify(_ text: String) -> Result {
        var detections: [Detection] = []
        let nsText: NSString = text as NSString

        for entry in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: entry.pattern, options: [.caseInsensitive]
            ) else { continue }
            let matches = regex.matches(
                in: text, range: NSRange(location: 0, length: nsText.length)
            )
            for match in matches {
                let matched: String = nsText.substring(with: match.range)
                if detections.contains(where: {
                    $0.range.intersection(match.range) != nil && $0.confidence >= entry.confidence
                }) {
                    continue
                }
                detections.append(Detection(
                    category: entry.category, text: matched,
                    confidence: entry.confidence, range: match.range
                ))
            }
        }

        return Result(detections: detections.sorted { $0.confidence > $1.confidence })
    }
}
