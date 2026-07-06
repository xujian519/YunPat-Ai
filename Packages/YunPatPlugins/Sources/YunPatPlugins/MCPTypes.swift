import Foundation

// MARK: - JSON-RPC 消息

public struct MCPRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: Int
    public let method: String
    public let params: MCPJSONValue?

    public init(method: String, id: Int = 1, params: MCPJSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        id = try container.decode(Int.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        params = try container.decodeIfPresent(MCPJSONValue.self, forKey: .params)
    }
}

public struct MCPResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: Int
    public let result: MCPJSONValue?
    public let error: MCPErrorResponse?

    public init(id: Int, result: MCPJSONValue? = nil, error: MCPErrorResponse? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct MCPErrorResponse: Codable, Sendable, Error {
    public let code: Int
    public let message: String
    public let data: MCPJSONValue?

    public init(code: Int = -1, message: String, data: MCPJSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

// MARK: - JSON Value (MCP 语义的灵活 JSON 表示)

public enum MCPJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([MCPJSONValue])
    case object([String: MCPJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let dbl = try? container.decode(Double.self) {
            self = .double(dbl)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if container.decodeNil() {
            self = .null
        } else if let arr = try? container.decode([MCPJSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: MCPJSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let val): try container.encode(val)
        case .int(let val): try container.encode(val)
        case .double(let val): try container.encode(val)
        case .bool(let val): try container.encode(val)
        case .null: try container.encodeNil()
        case .array(let val): try container.encode(val)
        case .object(let val): try container.encode(val)
        }
    }

    /// 尝试提取字符串值
    public var stringValue: String? {
        if case .string(let val) = self { return val }
        return nil
    }

    /// 尝试提取对象
    public var objectValue: [String: MCPJSONValue]? {
        if case .object(let val) = self { return val }
        return nil
    }

    /// 尝试从 String 解析 JSON 为 MCPJSONValue
    public static func parse(jsonString: String) -> MCPJSONValue? {
        guard let data = jsonString.data(using: .utf8),
              let value = try? JSONDecoder().decode(MCPJSONValue.self, from: data)
        else { return nil }
        return value
    }

    /// 序列化为 JSON 字符串
    public func jsonString(pretty: Bool = false) -> String {
        let encoder = JSONEncoder()
        if pretty { encoder.outputFormatting = .prettyPrinted }
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8)
        else { return "" }
        return str
    }
}

// MARK: - Tool 定义

public struct MCPToolDefinition: Codable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: MCPJSONValue

    public init(name: String, description: String, inputSchema: MCPJSONValue = .object([:])) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

// MARK: - Resource 定义

public struct MCPResource: Codable, Sendable {
    public let uri: String
    public let name: String
    public let description: String?
    public let mimeType: String?

    public init(uri: String, name: String, description: String? = nil, mimeType: String? = nil) {
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
    }
}

public struct MCPResourceContents: Codable, Sendable {
    public let uri: String
    public let mimeType: String?
    public let text: String?
    public let blob: String?

    public init(uri: String, mimeType: String? = nil, text: String? = nil, blob: String? = nil) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
        self.blob = blob
    }
}

// MARK: - Prompt 定义

public struct MCPPrompt: Codable, Sendable {
    public let name: String
    public let description: String?
    public let arguments: [MCPPromptArgument]?

    public init(name: String, description: String? = nil, arguments: [MCPPromptArgument]? = nil) {
        self.name = name
        self.description = description
        self.arguments = arguments
    }
}

public struct MCPPromptArgument: Codable, Sendable {
    public let name: String
    public let description: String?
    public let required: Bool?

    public init(name: String, description: String? = nil, required: Bool? = nil) {
        self.name = name
        self.description = description
        self.required = required
    }
}

public struct MCPPromptMessage: Codable, Sendable {
    public let role: String
    public let content: MCPJSONValue

    public init(role: String, content: MCPJSONValue) {
        self.role = role
        self.content = content
    }
}

// MARK: - MCP 传输层错误（与 JSON-RPC error 分开）

/// 传输层错误 — 用于 MCPTransport 实现中的连接/分帧问题
public struct MCPError: Error, Sendable {
    public let code: Int
    public let message: String
    public init(code: Int = -1, message: String) {
        self.code = code
        self.message = message
    }
}

public let MCPErrorDomain: String = "com.yunpat.mcp"

// MARK: - MCP 标准方法名

public enum MCPMethod: String, Sendable {
    case initialize
    case toolsList = "tools/list"
    case toolsCall = "tools/call"
    case resourcesList = "resources/list"
    case resourcesRead = "resources/read"
    case promptsList = "prompts/list"
    case promptsGet = "prompts/get"
    case ping
}
