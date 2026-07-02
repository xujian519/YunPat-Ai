import XCTest

@testable import YunPatCore
@testable import YunPatPlugins

final class PluginContextTests: XCTestCase {

    // MARK: - Basic Registration

    func testRegisterTool() async throws {
        let manifest = PluginManifest(id: "test.plugin", name: "Test", version: "1.0.0")
        let ctx = PluginContext(pluginID: "test.plugin", manifest: manifest)

        await ctx.register(name: "hello", description: "says hello") { _, _, _ in
            .handled("Hello!")
        }

        let handler: PluginToolHandler? = await ctx.handler(for: "test.plugin:hello")
        XCTAssertNotNil(handler)
    }

    func testToolNamePrefix() async throws {
        let manifest = PluginManifest(id: "my.plugin", name: "MyPlugin", version: "1.0.0")
        let ctx = PluginContext(pluginID: "my.plugin", manifest: manifest)

        await ctx.register(name: "greet", description: "greeting") { name, _, _ in
            .handled("Hi from \(name)")
        }

        let specs: [PluginToolSpec] = await ctx.allSpecs
        XCTAssertEqual(specs.first?.name, "my.plugin:greet")
    }

    // MARK: - Secret Injection

    func testSecretInjection() async throws {
        let manifest = PluginManifest(
            id: "secret.plugin", name: "SecretPlugin", version: "1.0.0",
            secrets: [
                PluginSecret(id: "api_key", label: "API Key", required: true)
            ]
        )
        let ctx = PluginContext(pluginID: "secret.plugin", manifest: manifest, secrets: ["api_key": "sk-12345"])

        await ctx.register(name: "call_api", description: "calls external API") { _, input, _ in
            let secret: [String: String]? = input["_secrets"] as? [String: String]
            let key: String = secret?["api_key"] ?? "none"
            return .handled("key=\(key)")
        }

        guard let handler = await ctx.handler(for: "secret.plugin:call_api") else { return XCTFail("No handler") }
        let result: PluginToolResult = await handler(
            "secret.plugin:call_api", [:],
            ToolContext(
                toolId: "", projectFolder: "/tmp", selectedProvider: .deepseek
            ))

        if case .handled(let text) = result {
            XCTAssertTrue(text.contains("sk-12345"), "Secret should be injected: \(text)")
        } else {
            XCTFail("Expected .handled")
        }
    }

    func testMissingRequiredSecret() async throws {
        let manifest = PluginManifest(
            id: "needkey.plugin", name: "NeedKey", version: "1.0.0",
            secrets: [PluginSecret(id: "api_key", label: "API Key", required: true)]
        )
        let ctx = PluginContext(pluginID: "needkey.plugin", manifest: manifest, secrets: [:])

        let hasSecrets: Bool = await ctx.hasRequiredSecrets
        XCTAssertFalse(hasSecrets)
    }

    func testHasRequiredSecrets() async throws {
        let manifest = PluginManifest(
            id: "haskey.plugin", name: "HasKey", version: "1.0.0",
            secrets: [PluginSecret(id: "api_key", label: "API Key", required: true)]
        )
        let ctx = PluginContext(pluginID: "haskey.plugin", manifest: manifest, secrets: ["api_key": "valid"])

        let hasSecrets: Bool = await ctx.hasRequiredSecrets
        XCTAssertTrue(hasSecrets)
    }

    // MARK: - ContextFolder Injection

    func testContextFolderInjection() async throws {
        let manifest = PluginManifest(id: "ctx.plugin", name: "CtxPlugin", version: "1.0.0")
        let ctx = PluginContext(pluginID: "ctx.plugin", manifest: manifest)

        await ctx.register(name: "check_ctx", description: "checks context folder") { _, input, _ in
            let folder: String = input["_context_folder"] as? String ?? "none"
            return .handled("folder=\(folder)")
        }

        guard let handler2 = await ctx.handler(for: "ctx.plugin:check_ctx") else { return XCTFail("No handler") }
        let result: PluginToolResult = await handler2(
            "ctx.plugin:check_ctx", [:],
            ToolContext(
                toolId: "", projectFolder: "/Users/test/work", selectedProvider: .deepseek
            ))

        if case .handled(let text) = result {
            XCTAssertTrue(text.contains("/Users/test/work"))
        } else {
            XCTFail("Expected .handled")
        }
    }
}
