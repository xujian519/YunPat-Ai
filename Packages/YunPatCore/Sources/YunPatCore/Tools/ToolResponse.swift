import Foundation

// MARK: - Standardized Tool Response Envelope

/// 统一工具响应信封 — 标准化 {ok, data} / {ok:false, error} 模式供模型判断
///
/// 对齐 Osaurus {ok, data} / {ok:false, error} 模式。
/// 模型通过 ok 字段精准判断成功/失败，避免散文本误判。
public struct ToolResponse: Sendable, Codable {
    /// 操作是否成功
    public let ok: Bool
    /// 成功数据的 JSON 值（ok=true 时有效）
    public let data: JSONValue?
    /// 错误信息（ok=false 时有效）
    public let error: ToolError?
    /// 非致命警告列表
    public let warnings: [String]?

    /// 工具错误 — 包含错误码、消息和修复建议
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

/// 递归 JSON 值类型 — 避免 Any 的非 Codable 问题，用于 ToolResponse.data 字段
///
/// 用于 ToolResponse.data 字段，支持 null/bool/number/string/array/object
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

// MARK: - JSONValue 便捷访问

public extension JSONValue {

    /// 字符串值（number 也转为字符串以兼容旧代码）
    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return String(value)
        default: return nil
        }
    }

    /// 整数值
    var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        default: return nil
        }
    }

    /// 双精度浮点值
    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        default: return nil
        }
    }

    /// 布尔值
    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        default: return nil
        }
    }

    /// 对象字典
    var objectValue: [String: JSONValue]? {
        if case .object(let dict) = self { return dict }
        return nil
    }

    /// 数组
    var arrayValue: [JSONValue]? {
        if case .array(let arr) = self { return arr }
        return nil
    }

    /// 下标访问（仅对 .object 有效）
    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    /// 从 [String: Any] 构建（向后兼容）
    static func from(_ any: Any) -> JSONValue {
        if any is NSNull { return .null }
        if let val = any as? Bool { return .bool(val) }
        if let val = any as? Int { return .number(Double(val)) }
        if let val = any as? Double { return .number(val) }
        if let val = any as? String { return .string(val) }
        if let val = any as? [Any] { return .array(val.map { .from($0) }) }
        if let val = any as? [String: Any] { return .object(val.mapValues { .from($0) }) }
        return .null
    }

    /// 转回 [String: Any]（向后兼容旧 ToolHandler 签名）
    func toAny() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let arr): return arr.map { $0.toAny() }
        case .object(let dict): return dict.mapValues { $0.toAny() }
        }
    }

    /// 字典形式的 [String: JSONValue] 转为 [String: Any]
    static func toAnyDict(_ dict: [String: JSONValue]) -> [String: Any] {
        dict.mapValues { $0.toAny() }
    }
}
