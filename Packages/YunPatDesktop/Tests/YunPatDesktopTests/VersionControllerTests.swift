import Foundation
import Testing

@testable import YunPatDesktop

struct VersionControllerTests {

    @Test func gitInitCommitLog() async throws {
        // Create a temporary directory for the test repo
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YunPatDesktop_VC_Test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let shell = ShellExecutor()
        let versionController = VersionController(workspaceRoot: tmpDir, shell: shell)

        // Init
        try await versionController.gitInit()

        // Configure git user for the test (required for commit)
        _ = try await shell.execute("git config user.email 'test@yunpat.ai'", cwd: tmpDir)
        _ = try await shell.execute("git config user.name 'Test'", cwd: tmpDir)

        // Create and stage a file
        let file = tmpDir.appendingPathComponent("test.txt")
        try "hello git".write(to: file, atomically: true, encoding: .utf8)
        try await versionController.stageAll()

        // Commit
        try await versionController.commit("initial commit")

        // Log
        let log: [VersionInfo] = try await versionController.log(limit: 5)
        #expect(log.count == 1, "Expected 1 commit, got \(log.count)")
        #expect(log[0].message == "initial commit")
        #expect(!log[0].hash.isEmpty)
    }
}
