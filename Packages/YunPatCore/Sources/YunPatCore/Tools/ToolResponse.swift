import Foundation

// MARK: - Standardized Tool Response Envelope

/// 统一工具响应信封 — 对齐 Osaurus {ok, data} / {ok:false, error} 模式
/// 模型通过 ok 字段精准判断成功/失败，避免散文本误判
public struct ToolResponse: Sendable, Codable {
    public let ok: Bool
    public let data: JSONValue?
    public let error: ToolError?
    public let warnings: [String]?

    public struct ToolError: Sendable, Codable, Equatable {
        public let code: String
        public let message: String
        public let hint: String?

        public init(code: String, message: String, hint: String? = nil) {
            self.code = code
            self.message = message
            self.hint = hint
        }
    }

    public init(ok: Bool, data: JSONValue?, error: ToolError?, warnings: [String]?) {
        self.ok = ok
        self.data = data
        self.error = error
        self.warnings = warnings
    }

    public static func okResp(data: JSONValue, warnings: [String]? = nil) -> ToolResponse {
        ToolResponse(ok: true, data: data, error: nil, warnings: warnings)
    }

    public static func errResp(
        code: ToolErrorCode, message: String, hint: String? = nil,
        warnings: [String]? = nil
    ) -> ToolResponse {
        ToolResponse(
            ok: false, data: nil,
            error: ToolError(code: code.rawValue, message: message, hint: hint),
            warnings: warnings
        )
    }

    /// 编码为 JSON 字符串，供 ToolHandlerResult.handled(String) 返回
    public func jsonString() -> String {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let raw: Data = try? encoder.encode(self) else {
            return #"{"ok":false,"error":{"code":"INTERNAL","message":"JSON encode failed"}}"#
        }
        return String(data: raw, encoding: .utf8) ?? "{}"
    }

    /// 尝试从字符串中解码 ToolResponse
    public static func tryParse(_ text: String) -> ToolResponse? {
        guard let raw: Data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ToolResponse.self, from: raw)
    }
}

// MARK: - JSONValue

/// 递归 JSON 值类型，避免 Any 的非 Codable 问题
/// 用于 ToolResponse.data 字段
public indirect enum JSONValue: Sendable, Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container: SingleValueDecodingContainer = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let val: Bool = try? container.decode(Bool.self) {
            self = .bool(val)
        } else if let val: Double = try? container.decode(Double.self) {
            self = .number(val)
        } else if let val: String = try? container.decode(String.self) {
            self = .string(val)
        } else if let val: [JSONValue] = try? container.decode([JSONValue].self) {
            self = .array(val)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let val): try container.encode(val)
        case .number(let val): try container.encode(val)
        case .string(let val): try container.encode(val)
        case .array(let val): try container.encode(val)
        case .object(let val): try container.encode(val)
        }
    }
}
