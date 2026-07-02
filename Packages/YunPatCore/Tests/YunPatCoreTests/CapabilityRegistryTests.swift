import XCTest

@testable import YunPatCore

final class CapabilityRegistryTests: XCTestCase {
    func testRegisterAndListCapability() async {
        let registry = CapabilityRegistry()
        let cap = CapabilityDefinition(name: "test.general", displayName: "通用", description: "通用问答")
        await registry.register(capability: cap)
        let caps = await registry.listCapabilities()
        XCTAssertEqual(caps.count, 1)
        XCTAssertEqual(caps.first?.name, "test.general")
    }

    func testListCapabilities_withoutRegistration_returnsEmpty() async {
        let registry = CapabilityRegistry()
        let caps = await registry.listCapabilities()
        XCTAssertTrue(caps.isEmpty)
    }

    func testRegisterBuiltinCapabilities_addsDefaults() async {
        let registry = CapabilityRegistry()
        await registry.registerBuiltinCapabilities()
        let caps = await registry.listCapabilities()
        XCTAssertFalse(caps.isEmpty)
        XCTAssertTrue(caps.contains { $0.name == "core.chat" })
    }
}
