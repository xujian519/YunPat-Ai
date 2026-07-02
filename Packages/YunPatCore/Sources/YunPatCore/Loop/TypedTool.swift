import Foundation

// MARK: - TypedTool 协议

/// 类型安全工具协议 — 通过 Decodable Args 实现编译期类型检查，自动桥接 ToolHandler
///
/// 对比裸 `ToolHandler` 闭包的优势：
/// - `Args` 为 Decodable 结构体，编译期类型检查
/// - 每个工具独立 struct，天然可测试
/// - `handler` 计算属性自动桥接到 `ToolHandler` 签名，不改动现有调度链
///
/// 使用示例:
/// ```swift
/// struct MyTool: TypedTool {
///     let name = "my_tool"
///     let description = "做什么的"
///     struct Args: Decodable, Sendable {
///         let query: String
///     }
///     func execute(input: Args, context: ToolContext) async throws -> ToolResponse {
///         ToolResponse.okResp(data: .string("result: \(input.query)"))
///     }
/// }
/// ```
public protocol TypedTool: Sendable {
    associatedtype Args: Decodable & Sendable
    var name: String { get }
    var description: String { get }
    /// JSON Schema 字符串（给 LLM 的 function calling 参数描述），默认 "{}"
    var parameters: String { get }
    func execute(input: Args, context: ToolContext) async throws -> ToolResponse
}

// MARK: - 默认桥接到 ToolHandler

extension TypedTool {
    /// JSON Schema 默认值（空 schema）
    public var parameters: String { "{}" }

    /// 生成 ToolSpec（供 ToolDispatch 注册）
    public var toolSpec: ToolSpec {
        ToolSpec(name: name, description: description, parameters: parameters)
    }

    /// 桥接为 ToolHandler 闭包，供 ToolDispatch.register() 使用
    public var handler: ToolHandler {
        { _, rawInput, ctx in
            // JSONValue → Data → Decodable Args（单次编码，无 JSONSerialization）
            guard let data = try? JSONEncoder().encode(JSONValue.object(rawInput)),
                let args = try? JSONDecoder().decode(Args.self, from: data)
            else {
                return .handled(
                    ToolResponse.errResp(code: .invalidArgs, message: "参数解析失败，期望类型: \(Args.self)").jsonString()
                )
            }
            do {
                return .handled(try await self.execute(input: args, context: ctx).jsonString())
            } catch {
                return .handled(
                    ToolResponse.errResp(code: .executionError, message: error.localizedDescription).jsonString()
                )
            }
        }
    }
}

// MARK: - TypedToolRegistry

/// 强类型工具注册表 — 统一注册 TypedTool 实例到 ToolDispatch，避免重复注册
///
/// 用法：
/// ```swift
/// await TypedToolRegistry.shared.register(ReadFileTool())
/// await TypedToolRegistry.shared.register(PatentSearchTool(searcher: mySearcher))
/// ```
public actor TypedToolRegistry {
    public static let shared: TypedToolRegistry = TypedToolRegistry()

    private var registered: Set<String> = []

    public init() {}

    /// 注册一个 TypedTool 到 ToolDispatch
    public func register<T: TypedTool>(_ tool: T) {
        guard !registered.contains(tool.name) else { return }
        registered.insert(tool.name)
        ToolDispatch.shared.register(
            name: tool.name,
            description: tool.description,
            handler: tool.handler
        )
    }

    /// 注销
    public func unregister(_ name: String) {
        registered.remove(name)
        ToolDispatch.shared.unregister(name: name)
    }

    /// 已注册的强类型工具名
    public var registeredNames: [String] { Array(registered) }
}
