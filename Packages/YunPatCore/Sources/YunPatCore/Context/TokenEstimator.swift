import Foundation
import YunPatNetworking

/// 中文友好的 token 估算
public enum TokenEstimator: Sendable {

    /// 每 token 的平均字符数（按 provider/语言）
    public static func charsPerToken(for provider: ModelProvider) -> Double {
        switch provider {
        case .deepseek, .glm:
            return 1.8       // 中文为主，~1.5-2 char/token
        case .openai, .anthropic:
            return 2.5       // 中英混合
        case .ollama, .mlx:
            return 2.0
        }
    }

    /// 估算文本的 token 数（按字符类型加权）
    public static func estimate(text: String, provider: ModelProvider) -> Int {
        // CJK 字符通常 1 char ≈ 1 token（含标点），ASCII/数字约 4 chars ≈ 1 token
        var effectiveCount = 0.0
        for char in text {
            if isCJK(char) {
                effectiveCount += 1.0
            } else if char.isWhitespace || char.isNewline {
                effectiveCount += 0.25
            } else {
                effectiveCount += 0.3
            }
        }
        return max(1, Int(ceil(effectiveCount)))
    }

    /// 判断字符是否为 CJK（中文/日文/韩文）
    private static func isCJK(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v)   // CJK Unified
            || (0x3400...0x4DBF).contains(v)   // CJK Extension A
            || (0x3000...0x303F).contains(v)   // CJK Symbols
            || (0xFF00...0xFFEF).contains(v)   // Halfwidth/Fullwidth
            || (0xAC00...0xD7AF).contains(v)   // Hangul (韩文)
            || (0x3040...0x309F).contains(v)   // Hiragana
            || (0x30A0...0x30FF).contains(v)   // Katakana
    }

    /// 估算消息数组的 token 数（含角色/格式开销）
    public static func estimate(messages: [Message], provider: ModelProvider) -> Int {
        var total = 0
        for msg in messages {
            total += estimate(text: msg.content, provider: provider)
            total += 4  // 角色/格式 per-message overhead
        }
        return total
    }

    /// 估算 ChatRequest 的总 token 数
    public static func estimate(request: ChatRequest, provider: ModelProvider) -> Int {
        var total = estimate(messages: request.messages, provider: provider)
        if let sp = request.systemPrompt {
            total += estimate(text: sp, provider: provider)
            total += 4  // system 角色开销
        }
        return total
    }
}

// MARK: - Token Budget

/// 上下文窗口预算计算
public struct ContextBudget: Sendable {
    public let window: Int                // 模型上下文窗口
    public let effectiveBudget: Int       // window × safetyMargin
    public let reservedSystem: Int        // system prompt
    public let reservedTools: Int         // tool schema
    public let reservedResponse: Int      // max_tokens
    public let safetyMargin: Double       // 默认 0.85

    public init(
        window: Int,
        safetyMargin: Double = 0.85,
        reservedSystem: Int = 2000,
        reservedTools: Int = 2000,
        reservedResponse: Int = 4096
    ) {
        self.window = window
        self.safetyMargin = safetyMargin
        self.effectiveBudget = Int(Double(window) * safetyMargin)
        self.reservedSystem = reservedSystem
        self.reservedTools = reservedTools
        self.reservedResponse = reservedResponse
    }

    /// 可用于 history 的 token 预算
    public var availableForHistory: Int {
        effectiveBudget - reservedSystem - reservedTools - reservedResponse
    }

    /// 从 ModelCapabilities 构造
    public init(capabilities: ModelCapabilities) {
        self.init(window: capabilities.maxContextTokens)
    }

    /// 标准窗口（128K 上下文，85% 安全边距）
    public static let standard = ContextBudget(window: 128_000)
}
