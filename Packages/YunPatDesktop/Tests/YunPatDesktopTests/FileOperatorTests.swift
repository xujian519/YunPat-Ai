import Foundation
import Testing
@testable import YunPatDesktop

struct FileOperatorTests {

    @Test func readWriteFile() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YunPatDesktop_FO_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let op = FileOperator(workspaceRoot: tmpDir)
        let content = "hello file operator".data(using: .utf8)!
        try await op.writeFile("test.txt", content: content)
        let read = try await op.readFile("test.txt")
        #expect(String(data: read, encoding: .utf8) == "hello file operator")
    }

    @Test func deleteFile() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YunPatDesktop_FO_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let op = FileOperator(workspaceRoot: tmpDir)
        try await op.writeFile("delete-me.txt", content: Data())
        try await op.deleteFile("delete-me.txt")
        #expect(!FileManager.default.fileExists(atPath: tmpDir.appendingPathComponent("delete-me.txt").path))
    }

    @Test func readOutsideWorkspaceThrows() async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YunPatDesktop_FO_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let op = FileOperator(workspaceRoot: tmpDir)
        do {
            _ = try await op.readFile("/etc/passwd")
            #expect(Bool(false), "Expected FileError.pathNotAllowed")
        } catch let error as FileError {
            guard case .pathNotAllowed(let path) = error else {
                #expect(Bool(false), "Wrong FileError case")
                return
            }
            #expect(path == "/etc/passwd")
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test func writeOutsideWorkspaceThrows() async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YunPatDesktop_FO_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let op = FileOperator(workspaceRoot: tmpDir)
        do {
            try await op.writeFile("/tmp/unauthorized.txt", content: Data())
            #expect(Bool(false), "Expected FileError.pathNotAllowed")
        } catch let error as FileError {
            guard case .pathNotAllowed(let path) = error else {
                #expect(Bool(false), "Wrong FileError case")
                return
            }
            #expect(path == "/tmp/unauthorized.txt")
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test func relativePathResolvesToWorkspace() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("YunPatDesktop_FO_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmpDir.appendingPathComponent("subdir"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let op = FileOperator(workspaceRoot: tmpDir)
        let content = "relative".data(using: .utf8)!
        try await op.writeFile("subdir/file.txt", content: content)
        let read = try await op.readFile("subdir/file.txt")
        #expect(String(data: read, encoding: .utf8) == "relative")
    }
}
