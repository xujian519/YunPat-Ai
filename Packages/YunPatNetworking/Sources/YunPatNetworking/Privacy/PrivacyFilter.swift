import Foundation

/// PII 脱敏过滤器 — 云端发送前对请求文本进行正则 + 客户自定义词表脱敏
///
/// MVP 先上正则层，后期可接 on-device 分类器（oMLX / privacy-filter）。
/// 支持 ChatRequest 全量脱敏、单文本脱敏、流式回复反脱敏（unscrub）。
public actor PrivacyFilter { // swiftlint:disable:this type_body_length

    public static let shared: PrivacyFilter = PrivacyFilter()
    private let registry: SensitiveTermsRegistry
    private var placeholderCounter: Int = 0

    public init(registry: SensitiveTermsRegistry = .shared) {
        self.registry = registry
    }

    // MARK: - Public API

    /// 对 ChatRequest 的所有文本内容进行脱敏
    public func scrub(
        request: ChatRequest,
        provider: ModelProvider,
        caseId: String?
    ) async throws -> (request: ChatRequest, result: ScrubResult) {
        guard !provider.isLocal else {
            return (request, ScrubResult(scrubbedText: "", detections: [], placeholderMap: [:], blocked: false))
        }

        var allDetections: [Detection] = []
        var totalMap: [String: String] = [:]
        let scrubbedSystemPrompt: String?
        if let systemPrompt = request.systemPrompt {
            let result: ScrubResult = await applyAll(to: systemPrompt, caseId: caseId)
            scrubbedSystemPrompt = result.scrubbedText
            allDetections += result.detections
            for (key, val) in result.placeholderMap { totalMap[key] = val }
        } else {
            scrubbedSystemPrompt = nil
        }

        // 2. 脱敏 messages
        var scrubbedMessages: [Message] = []
        for msg in request.messages {
            let result: ScrubResult = await applyAll(to: msg.content, caseId: caseId)
            scrubbedMessages.append(
                Message(
                    role: msg.role,
                    content: result.scrubbedText,
                    toolCallID: msg.toolCallID,
                    name: msg.name
                ))
            allDetections += result.detections
            for (key, val) in result.placeholderMap { totalMap[key] = val }
        }

        // 3. fail-closed: 脱敏后复扫
        let combinedAfter: String = (scrubbedSystemPrompt ?? "") + scrubbedMessages.map(\.content).joined()
        let residual: [Detection] = try await scanResidual(combinedAfter, caseId: caseId)
        let blocked: Bool = !residual.isEmpty

        let result: ScrubResult = ScrubResult(
            scrubbedText: combinedAfter,
            detections: allDetections + residual,
            placeholderMap: totalMap,
            blocked: blocked
        )

        let scrubbedReq: ChatRequest = ChatRequest(
            model: request.model,
            messages: scrubbedMessages,
            systemPrompt: scrubbedSystemPrompt,
            temperature: request.temperature,
            maxTokens: request.maxTokens
        )
        return (scrubbedReq, result)
    }

    /// 对单段文本脱敏
    public func scrub(text: String, provider: ModelProvider, caseId: String?) async -> ScrubResult {
        guard !provider.isLocal else {
            return ScrubResult(scrubbedText: text, detections: [], placeholderMap: [:], blocked: false)
        }
        return await applyAll(to: text, caseId: caseId)
    }

    /// 流式 unscrub：用 placeholderMap 将占位符替换回原文
    /// nonisolated 因为不访问 actor 可变状态（replacePlaceholders 也是 nonisolated）
    nonisolated public func unscrub(
        stream: AsyncThrowingStream<ChatChunk, Error>,
        map: [String: String]
    ) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                do {
                    for try await chunk in stream {
                        switch chunk {
                        case .text(let text):
                            continuation.yield(.text(self?.replacePlaceholders(in: text, map: map) ?? text))
                        case .toolCall(let id, let name, let args):
                            continuation.yield(
                                .toolCall(
                                    id: id, name: name,
                                    arguments: self?.replacePlaceholders(in: args, map: map) ?? args
                                ))
                        case .toolCallDelta(let id, let args):
                            continuation.yield(
                                .toolCallDelta(
                                    id: id,
                                    arguments: self?.replacePlaceholders(in: args, map: map) ?? args
                                ))
                        case .finish(let reason, let usage):
                            continuation.yield(.finish(reason: reason, usage: usage))
                        case .error(let error):
                            continuation.yield(.error(error))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Internal

    /// 对文本依次应用所有脱敏模式（正则 → 自定义词表）
    private func applyAll(to text: String, caseId: String?) async -> ScrubResult {
        var current: String = text
        var allDetections: [Detection] = []
        var map: [String: String] = [:]

        let regexPatterns: [PatternEntry] = makeRegexPatterns()
        for entry in regexPatterns {
            let resultScrub: RegexResult = applyRegex(
                pattern: entry.pattern, kind: entry.kind, source: entry.source, to: current)
            current = resultScrub.text
            allDetections += resultScrub.detections
            for (key, val) in resultScrub.placeholderMap { map[key] = val }
        }

        // 客户自定义敏感词
        let terms: [SensitiveTermsRegistry.Term] = await registry.terms(forCase: caseId)
        let customResult: RegexResult = applyCustomTerms(terms, to: current)
        current = customResult.text
        allDetections += customResult.detections
        for (key, val) in customResult.placeholderMap { map[key] = val }

        return ScrubResult(scrubbedText: current, detections: allDetections, placeholderMap: map, blocked: false)
    }

    /// fail-closed 复扫
    private func scanResidual(_ text: String, caseId: String?) async throws -> [Detection] {
        var residuals: [Detection] = []
        let regexPatterns = makeRegexPatterns()
        let nsText: NSString = text as NSString
        for entry in regexPatterns {
            let regex = try NSRegularExpression(pattern: entry.pattern, options: [])
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let matchStr = nsText.substring(with: match.range)
                if matchStr.hasPrefix("[") && matchStr.hasSuffix("]") { continue }
                residuals.append(
                    Detection(
                        kind: entry.kind, entity: matchStr,
                        placeholder: "[RESIDUAL_\(matchStr.prefix(20))]",
                        range: match.range, source: entry.source
                    ))
            }
        }
        return residuals
    }

    /// 对一段文本应用单个正则，替换匹配项为占位符
    private struct RegexResult: Sendable {
        var text: String
        var detections: [Detection]
        var placeholderMap: [String: String]
    }

    private func applyRegex(pattern: String, kind: EntityKind, source: DetectionSource,
                            to text: String) -> RegexResult {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return RegexResult(text: text, detections: [], placeholderMap: [:])
        }

        let nsText: NSString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var detections: [Detection] = []
        var map: [String: String] = [:]
        var mutable: String = text

        // 从后向前替换，保持 range 有效
        for match in matches.reversed() {
            let entity = nsText.substring(with: match.range)
            // 跳过已经是占位符的内容
            if entity.hasPrefix("[") && entity.hasSuffix("]") { continue }
            // 跳过数字范围内不合理值（过滤过短/过长的误匹配）
            guard isValidDetection(entity, kind: kind) else { continue }

            let placeholder = nextPlaceholder(kind: kind)
            map[placeholder] = entity

            if let range = Range(match.range, in: mutable) {
                mutable.replaceSubrange(range, with: placeholder)
            }

            detections.append(
                Detection(
                    kind: kind, entity: entity, placeholder: placeholder,
                    range: match.range, source: source
                ))
        }

        return RegexResult(text: mutable, detections: detections, placeholderMap: map)
    }

    /// 应用自定义敏感词表
    private func applyCustomTerms(_ terms: [SensitiveTermsRegistry.Term], to text: String) -> RegexResult {
        var mutable: String = text
        var detections: [Detection] = []
        var map: [String: String] = [:]

        let nsText: NSString = mutable as NSString
        for term in terms {
            guard !term.value.isEmpty else { continue }
            // 大小写/全半角不敏感
            let pattern = NSRegularExpression.escapedPattern(for: term.value)
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let matches = regex.matches(in: mutable, range: NSRange(location: 0, length: nsText.length))

            for match in matches.reversed() {
                let entity = nsText.substring(with: match.range)
                if entity.hasPrefix("[") && entity.hasSuffix("]") { continue }
                let placeholder = nextPlaceholder(kind: term.kind)
                map[placeholder] = entity
                if let range = Range(match.range, in: mutable) {
                    mutable.replaceSubrange(range, with: placeholder)
                }
                detections.append(
                    Detection(
                        kind: term.kind, entity: entity, placeholder: placeholder,
                        range: match.range, source: .customList
                    ))
            }
        }

        return RegexResult(text: mutable, detections: detections, placeholderMap: map)
    }

    // MARK: - Regex Patterns

    private struct PatternEntry: Sendable {
        let kind: EntityKind
        let pattern: String
        let source: DetectionSource
    }

    private func makeRegexPatterns() -> [PatternEntry] {
        [
            PatternEntry(kind: .email, pattern: #"[\w.+-]+@[\w.-]+\.\w{2,}"#, source: .regex),
            PatternEntry(kind: .custom, pattern: #"https?://[^\s<>"']+"#, source: .regex),  // swiftlint:disable:this line_length
            PatternEntry(
                kind: .unifiedSocialCreditCode,
                pattern: #"(?<!\d)(?!\d{18})[0-9A-HJ-NPQRTUWXY]{18}(?!\d)"#,
                source: .regex
            ),
            PatternEntry(kind: .idNumber, pattern: #"(?<!\d)\d{17}[\dXx](?!\d)"#, source: .regex),
            PatternEntry(kind: .bankCard, pattern: #"(?<!\d)\d{16,19}(?!\d)"#, source: .regex),
            PatternEntry(kind: .phone, pattern: #"(?<!\d)1[3-9]\d{9}(?!\d)"#, source: .regex),
            PatternEntry(kind: .phone, pattern: #"(?<!\d)0\d{2,3}[-\s]?\d{7,8}(?!\d)"#, source: .regex),
            PatternEntry(kind: .idNumber, pattern: #"(?<!\d)\d{15}(?!\d)"#, source: .regex)
        ]
    }

    /// 过滤不合理匹配（避免误伤纯数字字段如申请号、日期等）
    private func isValidDetection(_ entity: String, kind: EntityKind) -> Bool {
        switch kind {
        case .phone:
            // 手机号不能全是相同数字（如 11111111111）
            if Set(entity).count == 1 { return false }
            return true
        case .idNumber:
            // 身份证需校验位粗略检查
            return entity.count >= 15
        case .bankCard:
            return entity.count >= 16
        case .unifiedSocialCreditCode:
            return entity.count == 18
        default:
            return true
        }
    }

    // MARK: - Placeholder

    private func nextPlaceholder(kind: EntityKind) -> String {
        placeholderCounter += 1
        let prefix: String
        switch kind {
        case .email: prefix = "EMAIL"
        case .phone: prefix = "PHONE"
        case .idNumber: prefix = "ID"
        case .bankCard: prefix = "BANK"
        case .unifiedSocialCreditCode: prefix = "USCC"
        case .applicantName: prefix = "APPLICANT"
        case .inventorName: prefix = "INVENTOR"
        case .custom: prefix = "CUSTOM"
        }
        return "[\(prefix)_\(placeholderCounter)]"
    }

    /// 替换文本中的占位符为原文
    nonisolated private func replacePlaceholders(in text: String, map: [String: String]) -> String {
        var result: String = text
        for (placeholder, original) in map {
            result = result.replacingOccurrences(of: placeholder, with: original)
        }
        return result
    }
}
