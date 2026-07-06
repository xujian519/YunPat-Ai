import Foundation

/// MCP 服务端 — 处理 JSON-RPC 请求，支持工具、资源和提示词
///
/// 双模式运行：
/// - 嵌入式：通过 `handleRequest(_:)` 直接处理 Data → Data
/// - 独立进程：通过 `start()` 监听 stdin/stdout（Content-Length 分帧）
public actor MCPServer {
    private var toolRegistry: [String: (MCPToolDefinition, @Sendable (MCPJSONValue) async throws -> MCPJSONValue)] = [:]
    private var resourceRegistry: [String: MCPResourceDescriptor] = [:]
    private var promptRegistry: [String: MCPPromptDescriptor] = [:]

    public init() {}

    // MARK: - 工具注册

    public func registerTool(
        _ tool: MCPToolDefinition,
        handler: @escaping @Sendable (MCPJSONValue) async throws -> MCPJSONValue
    ) {
        toolRegistry[tool.name] = (tool, handler)
    }

    public func unregisterTool(_ name: String) {
        toolRegistry.removeValue(forKey: name)
    }

    public var registeredTools: [MCPToolDefinition] {
        Array(toolRegistry.values).map { $0.0 }
    }

    // MARK: - 资源注册

    /// 注册一个静态资源
    public func registerResource(
        _ resource: MCPResource, contents: MCPResourceContents
    ) {
        let key: String = resource.uri
        resourceRegistry[key] = .staticResource(contents: contents, resource: resource)
    }

    /// 注册一个动态资源（每次读取时调用 handler）
    public func registerResource(
        _ resource: MCPResource,
        handler: @escaping @Sendable () async throws -> MCPResourceContents
    ) {
        let key: String = resource.uri
        resourceRegistry[key] = .dynamicResource(handler: handler, resource: resource)
    }

    public var registeredResources: [MCPResource] {
        resourceRegistry.values.map { $0.resource }
    }

    // MARK: - 提示词注册

    public func registerPrompt(
        _ prompt: MCPPrompt,
        handler: @escaping @Sendable ([String: String]?) async throws -> [MCPPromptMessage]
    ) {
        let key: String = prompt.name
        promptRegistry[key] = MCPPromptDescriptor(prompt: prompt, handler: handler)
    }

    public var registeredPrompts: [MCPPrompt] {
        Array(promptRegistry.values).map { $0.prompt }
    }

    // MARK: - 请求处理

    /// 处理单个 JSON-RPC 请求
    public func handleRequest(_ payload: Data) async -> Data {
        let request: MCPRequest
        do {
            request = try JSONDecoder().decode(MCPRequest.self, from: payload)
        } catch {
            let errorResp = MCPResponse(
                id: 0,
                error: MCPErrorResponse(code: -32700, message: "Parse error: \(error.localizedDescription)")
            )
            return (try? JSONEncoder().encode(errorResp)) ?? Data()
        }

        let response: MCPResponse
        switch request.method {
        case MCPMethod.initialize.rawValue:
            response = handleInitialize(request: request)
        case MCPMethod.toolsList.rawValue:
            response = handleToolsList(request: request)
        case MCPMethod.toolsCall.rawValue:
            response = await handleToolsCall(request: request)
        case MCPMethod.resourcesList.rawValue:
            response = handleResourcesList(request: request)
        case MCPMethod.resourcesRead.rawValue:
            response = await handleResourcesRead(request: request)
        case MCPMethod.promptsList.rawValue:
            response = handlePromptsList(request: request)
        case MCPMethod.promptsGet.rawValue:
            response = await handlePromptsGet(request: request)
        case MCPMethod.ping.rawValue:
            response = MCPResponse(id: request.id, result: .object([:]))
        default:
            response = MCPResponse(
                id: request.id,
                error: MCPErrorResponse(code: -32601, message: "Method not found: \(request.method)")
            )
        }
        return (try? JSONEncoder().encode(response)) ?? Data()
    }

    // MARK: - 独立进程模式

    /// 在 stdin/stdout 上以 Content-Length 分帧运行
    public func start() async throws {
        let stdin = FileHandle.standardInput
        let stdout = FileHandle.standardOutput
        while true {
            let payload: Data
            do {
                payload = try StdioMCPTransport.readFrame(from: stdin)
            } catch {
                break
            }
            let responseData: Data = await handleRequest(payload)
            let header: String = "Content-Length: \(responseData.count)\r\n\r\n"
            stdout.write(Data(header.utf8))
            stdout.write(responseData)
        }
    }

    // MARK: - Handler Implementations

    private func handleInitialize(request: MCPRequest) -> MCPResponse {
        MCPResponse(
            id: request.id,
            result: .object([
                "protocolVersion": .string("2024-11-05"),
                "capabilities": .object([
                    "tools": .object([:]),
                    "resources": .object([:]),
                    "prompts": .object([:])
                ]),
                "serverInfo": .object([
                    "name": .string("YunPat-MCP"),
                    "version": .string("1.0.0")
                ])
            ])
        )
    }

    private func handleToolsList(request: MCPRequest) -> MCPResponse {
        let tools: [MCPJSONValue] = toolRegistry.values.map { tool, _ in
            .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": tool.inputSchema
            ])
        }
        return MCPResponse(id: request.id, result: .object(["tools": .array(tools)]))
    }

    private func handleToolsCall(request: MCPRequest) async -> MCPResponse {
        guard let params = request.params?.objectValue,
              let name = params["name"]?.stringValue
        else {
            return MCPResponse(id: request.id, error: MCPErrorResponse(code: -32602, message: "Missing tool name"))
        }
        guard let (_, handler) = toolRegistry[name] else {
            return MCPResponse(
                id: request.id,
                error: MCPErrorResponse(code: -32602, message: "Tool not found: \(name)")
            )
        }
        let arguments: MCPJSONValue = params["arguments"] ?? .object([:])
        do {
            let result: MCPJSONValue = try await handler(arguments)
            let text = result.jsonString()
            let contentItem: MCPJSONValue = .object([
                "type": .string("text"),
                "text": .string(text)
            ])
            return MCPResponse(id: request.id, result: .object(["content": .array([contentItem])]))
        } catch {
            return MCPResponse(id: request.id, error: MCPErrorResponse(message: String(describing: error)))
        }
    }

    private func handleResourcesList(request: MCPRequest) -> MCPResponse {
        let resources: [MCPJSONValue] = resourceRegistry.values.map { desc in
            let res: MCPResource = desc.resource
            return .object([
                "uri": .string(res.uri),
                "name": .string(res.name),
                "description": res.description.map { .string($0) } ?? .null,
                "mimeType": res.mimeType.map { .string($0) } ?? .null
            ])
        }
        return MCPResponse(id: request.id, result: .object(["resources": .array(resources)]))
    }

    private func handleResourcesRead(request: MCPRequest) async -> MCPResponse {
        guard let params = request.params?.objectValue,
              let uri = params["uri"]?.stringValue
        else {
            return MCPResponse(id: request.id, error: MCPErrorResponse(code: -32602, message: "Missing resource uri"))
        }
        guard let descriptor = resourceRegistry[uri] else {
            return MCPResponse(
                id: request.id,
                error: MCPErrorResponse(code: -32602, message: "Resource not found: \(uri)")
            )
        }
        do {
            let contents: MCPResourceContents
            switch descriptor {
            case .staticResource(let staticContents, _):
                contents = staticContents
            case .dynamicResource(let handler, _):
                contents = try await handler()
            }
            let contentsData = try JSONEncoder().encode(contents)
            let contentsVal = try JSONDecoder().decode(MCPJSONValue.self, from: contentsData)
            return MCPResponse(id: request.id, result: .object(["contents": .array([contentsVal])]))
        } catch {
            return MCPResponse(id: request.id, error: MCPErrorResponse(message: String(describing: error)))
        }
    }

    private func handlePromptsList(request: MCPRequest) -> MCPResponse {
        let prompts: [MCPJSONValue] = promptRegistry.values.map { desc in
            let prompt: MCPPrompt = desc.prompt
            var obj: [String: MCPJSONValue] = ["name": .string(prompt.name)]
            if let descText = prompt.description { obj["description"] = .string(descText) }
            if let args = prompt.arguments {
                obj["arguments"] = .array(args.map { arg in
                    var aObj: [String: MCPJSONValue] = ["name": .string(arg.name)]
                    if let descr = arg.description { aObj["description"] = .string(descr) }
                    if let req = arg.required { aObj["required"] = .bool(req) }
                    return .object(aObj)
                })
            }
            return .object(obj)
        }
        return MCPResponse(id: request.id, result: .object(["prompts": .array(prompts)]))
    }

    private func handlePromptsGet(request: MCPRequest) async -> MCPResponse {
        guard let params = request.params?.objectValue,
              let name = params["name"]?.stringValue
        else {
            return MCPResponse(id: request.id, error: MCPErrorResponse(code: -32602, message: "Missing prompt name"))
        }
        guard let descriptor = promptRegistry[name] else {
            return MCPResponse(
                id: request.id,
                error: MCPErrorResponse(code: -32602, message: "Prompt not found: \(name)")
            )
        }
        let args: [String: String]?
        if let argsObj = params["arguments"]?.objectValue {
            args = argsObj.compactMapValues { $0.stringValue }
        } else {
            args = nil
        }
        do {
            let messages: [MCPPromptMessage] = try await descriptor.handler(args)
            let messagesData = try JSONEncoder().encode(messages)
            let messagesVal = try JSONDecoder().decode(MCPJSONValue.self, from: messagesData)
            return MCPResponse(id: request.id, result: .object(["messages": messagesVal]))
        } catch {
            return MCPResponse(id: request.id, error: MCPErrorResponse(message: String(describing: error)))
        }
    }
}

// MARK: - Resource Descriptor

enum MCPResourceDescriptor {
    case staticResource(contents: MCPResourceContents, resource: MCPResource)
    case dynamicResource(handler: @Sendable () async throws -> MCPResourceContents, resource: MCPResource)

    var resource: MCPResource {
        switch self {
        case .staticResource(_, let res): return res
        case .dynamicResource(_, let res): return res
        }
    }
}

// MARK: - Prompt Descriptor

struct MCPPromptDescriptor {
    let prompt: MCPPrompt
    let handler: @Sendable ([String: String]?) async throws -> [MCPPromptMessage]
}
