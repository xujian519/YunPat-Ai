import Testing
@testable import YunPatDesktop

struct ShellExecutorTests {

    @Test func echoReturnsOutput() async throws {
        let executor = ShellExecutor()
        let output = try await executor.execute("echo hello world")
        #expect(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
        #expect(output.exitCode == 0)
    }
    @Test func blockedCommandThrows() async {
        let executor = ShellExecutor(allowedCommands: ["echo"]) // rm not in allowlist
        do {
            _ = try await executor.execute("rm -rf /tmp/test")
            #expect(Bool(false), "Expected ShellError.commandNotAllowed, but no error thrown")
        } catch let error as ShellError {
            guard case .commandNotAllowed(let cmd) = error else {
                #expect(Bool(false), "Wrong ShellError case")
                return
            }
            #expect(cmd == "rm")
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
}
