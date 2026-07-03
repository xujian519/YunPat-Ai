import XCTest // swiftlint:disable:this file_name

@testable import YunPatPlugins

// MARK: - PluginSecret Tests

final class PluginSecretTests: XCTestCase {

    // MARK: Secret Definition

    func testSecretDefinition() {
        let secret = PluginSecret(
            id: "api_key",
            label: "OpenWeather API Key",
            description: "用于获取天气数据",
            required: true,
            url: "https://openweathermap.org/api_keys"
        )

        XCTAssertEqual(secret.id, "api_key")
        XCTAssertEqual(secret.label, "OpenWeather API Key")
        XCTAssertEqual(secret.description, "用于获取天气数据")
        XCTAssertTrue(secret.required)
        XCTAssertEqual(secret.url, "https://openweathermap.org/api_keys")
    }

    func testOptionalSecret() {
        let secret = PluginSecret(
            id: "optional_token",
            label: "Optional Token",
            required: false
        )

        XCTAssertEqual(secret.id, "optional_token")
        XCTAssertEqual(secret.label, "Optional Token")
        XCTAssertFalse(secret.required)
        XCTAssertNil(secret.description)
        XCTAssertNil(secret.url)
    }

    func testHelpText() {
        let secret = PluginSecret(
            id: "key", label: "Key",
            description: "用于调用 API",
            url: "https://example.com/api-keys"
        )
        let help = secret.helpText
        XCTAssertTrue(help.contains("用于调用 API"))
        XCTAssertTrue(help.contains("https://example.com/api-keys"))
    }

    // MARK: Manifest Integration

    func testManifestWithSecrets() {
        let secret = PluginSecret(id: "api_key", label: "API Key", required: true)

        let manifest = PluginManifest(
            id: "com.example.plugin",
            name: "Example Plugin",
            version: "1.0.0",
            level: .tool,
            description: "A test plugin",
            author: "Test Author",
            secrets: [secret]
        )

        XCTAssertEqual(manifest.secrets.count, 1, "Should have 1 secret")
        XCTAssertEqual(manifest.secrets.first?.id, "api_key")
        XCTAssertEqual(manifest.secrets.first?.label, "API Key")
        XCTAssertTrue(manifest.secrets.first?.required ?? false)
    }

    func testManifestWithoutSecrets() {
        let manifest = PluginManifest(
            id: "com.example.plugin",
            name: "Example Plugin",
            version: "1.0.0",
            level: .tool,
            description: "A test plugin",
            author: "Test Author"
        )

        XCTAssertTrue(manifest.secrets.isEmpty, "Should have no secrets by default")
    }
}
