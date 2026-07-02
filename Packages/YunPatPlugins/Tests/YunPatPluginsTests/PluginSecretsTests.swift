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

        XCTAssertNotNil(manifest.secrets)
        XCTAssertEqual(manifest.secrets?.count, 1)
        XCTAssertEqual(manifest.secrets?.first?.id, "api_key")
        XCTAssertEqual(manifest.secrets?.first?.label, "API Key")
        XCTAssertTrue(manifest.secrets?.first?.required ?? false)
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

        XCTAssertNil(manifest.secrets)
    }

    func testManifestWithSha256() {
        let expectedHash: String = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"

        let manifest = PluginManifest(
            id: "com.example.plugin",
            name: "Example Plugin",
            version: "1.0.0",
            level: .tool,
            description: "A test plugin",
            author: "Test Author",
            sha256: expectedHash
        )

        XCTAssertEqual(manifest.sha256, expectedHash)
        XCTAssertNotNil(manifest.sha256)
    }

    func testManifestWithSignature() {
        let expectedSig: String = "MEUCIQDx...base64signature...=="

        let manifest = PluginManifest(
            id: "com.example.plugin",
            name: "Example Plugin",
            version: "1.0.0",
            level: .tool,
            description: "A test plugin",
            author: "Test Author",
            signature: expectedSig
        )

        XCTAssertEqual(manifest.signature, expectedSig)
        XCTAssertNotNil(manifest.signature)
    }
}
