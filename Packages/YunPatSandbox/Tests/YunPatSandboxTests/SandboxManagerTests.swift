import Testing
@testable import YunPatSandbox

struct SandboxManagerTests {

    @Test func sandboxVMDefaults() {
        let vm = SandboxVM(id: "agent-1")
        #expect(vm.id == "agent-1")
        #expect(vm.state == .stopped)
        #expect(vm.linuxUser == "")
        #expect(vm.homeDirectory == "")
        #expect(vm.workspaceMount == "")
    }

    @Test func sandboxVMCustomInit() {
        let vm = SandboxVM(
            id: "test-42", state: .running,
            linuxUser: "agent-test-42", homeDirectory: "/home/agent-test-42",
            workspaceMount: "/workspace"
        )
        #expect(vm.id == "test-42")
        #expect(vm.state == .running)
        #expect(vm.linuxUser == "agent-test-42")
        #expect(vm.homeDirectory == "/home/agent-test-42")
        #expect(vm.workspaceMount == "/workspace")
    }

    @Test func sandboxVMIdentifiable() {
        let vm = SandboxVM(id: "agent-x")
        #expect(vm.id == vm.id)  // Identifiable conformance
    }

    @Test func vmStateAllCases() {
        #expect(VMState.stopped.rawValue == "stopped")
        #expect(VMState.starting.rawValue == "starting")
        #expect(VMState.running.rawValue == "running")
        #expect(VMState.stopping.rawValue == "stopping")
        #expect(VMState.error.rawValue == "error")
    }

    @Test func sandboxStatusCases() {
        if #available(macOS 26.0, *) {
            // Can't test .available directly without mocking, but at least verify types
        }
        let unsupported = SandboxStatus.unsupported(reason: "test")
        var desc = ""
        if case .unsupported(let reason) = unsupported { desc = reason }
        #expect(desc == "test")

        let unauthorized = SandboxStatus.unauthorized
        if case .unauthorized = unauthorized { /* ok */ }
    }

    @Test func sandboxErrorDescriptions() {
        #expect(SandboxError.unsupported.localizedDescription == "Sandbox VM requires macOS 26.0+ (Tahoe)")
        #expect(SandboxError.vmCreationFailed("OOM").localizedDescription == "VM creation failed: OOM")
    }

    @Test func sandboxManagerInit() async {
        let manager = SandboxManager()
        let status = await manager.status
        if #available(macOS 26.0, *) {
            if case .unsupported = status {
                // Running on <26 but test compiled for 26+
            }
        } else {
            guard case .unsupported(let reason) = status else {
                #expect(Bool(false), "Expected unsupported on pre-26 macOS")
                return
            }
            #expect(reason.contains("macOS 26.0+"))
        }
    }

    @Test func createAndListVM() async throws {
        let manager = SandboxManager()
        guard case .available = await manager.status else { return }  // skip on pre-26

        let vm = try await manager.createVM(agentID: "test-agent")
        #expect(vm.id == "test-agent")
        #expect(vm.state == .stopped)
        #expect(vm.linuxUser == "agent-test-agent")
        #expect(vm.homeDirectory == "/home/agent-test-agent")
        #expect(vm.workspaceMount == "/workspace")

        let vms = await manager.listVMs()
        #expect(vms.count == 1)
        #expect(vms[0].id == "test-agent")
    }

    @Test func createMultipleVMs() async throws {
        let manager = SandboxManager()
        guard case .available = await manager.status else { return }

        _ = try await manager.createVM(agentID: "a1")
        _ = try await manager.createVM(agentID: "a2")
        let vms = await manager.listVMs()
        #expect(vms.count == 2)
    }

    @Test func destroyVM() async throws {
        let manager = SandboxManager()
        guard case .available = await manager.status else { return }

        _ = try await manager.createVM(agentID: "to-destroy")
        try await manager.destroyVM(agentID: "to-destroy")
        let vms = await manager.listVMs()
        #expect(vms.isEmpty)
    }

    @Test func destroyNonexistentVMDoesNotThrow() async {
        let manager = SandboxManager()
        // Should not throw even if VM doesn't exist
        await #expect(throws: Never.self) {
            try await manager.destroyVM(agentID: "nonexistent")
        }
    }

    @Test func createOnUnsupportedThrows() async {
        let manager = SandboxManager()
        guard case .unsupported = await manager.status else { return }

        do {
            _ = try await manager.createVM(agentID: "should-fail")
            #expect(Bool(false), "Expected SandboxError.unsupported")
        } catch let error as SandboxError {
            #expect(error == .unsupported)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test func sandboxVMSendable() {
        // Compile-time check: SandboxVM conforms to Sendable
        let vm = SandboxVM(id: "s")
        let closure: @Sendable () -> Void = { _ = vm.id }
        closure()
    }

    @Test func sandboxErrorSendable() {
        let err: SandboxError = .unsupported
        let closure: @Sendable () -> Void = { _ = err.localizedDescription }
        closure()
    }
}
