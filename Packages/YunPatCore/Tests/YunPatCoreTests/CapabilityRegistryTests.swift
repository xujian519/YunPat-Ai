import XCTest

@testable import YunPatCore

final class CapabilityRegistryTests: XCTestCase {
    func testRegisterAndListCapability() {
        let registry = CapabilityRegistry()
        let cap = CapabilityDefinition(name: "test.general", displayName: "通用", description: "通用问答")
        registry.register(capability: cap)
        XCTAssertEqual(registry.listCapabilities().count, 1)
        XCTAssertEqual(registry.listCapabilities().first?.name, "test.general")
    }

    func testListCapabilities_withoutRegistration_returnsEmpty() {
        let registry = CapabilityRegistry()
        XCTAssertTrue(registry.listCapabilities().isEmpty)
    }

    func testRegisterBuiltinCapabilities_addsDefaults() {
        let registry = CapabilityRegistry()
        registry.registerBuiltinCapabilities()
        let caps = registry.listCapabilities()
        XCTAssertFalse(caps.isEmpty)
        XCTAssertTrue(caps.contains { $0.name == "core.chat" })
    }
}
