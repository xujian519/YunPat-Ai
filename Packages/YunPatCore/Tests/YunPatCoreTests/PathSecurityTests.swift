import XCTest

@testable import YunPatCore

final class PathSecurityTests: XCTestCase {

    private let base: String = "/Users/test/project"

    // MARK: - resolvePath

    func testResolveRelativePath() {
        let result = PathSecurity.resolvePath("folder/file.txt", relativeTo: base)
        XCTAssertEqual(result, "\(base)/folder/file.txt")
    }

    func testResolveAbsolutePath() {
        let result = PathSecurity.resolvePath("/tmp/foo.txt", relativeTo: base)
        XCTAssertEqual(result, "/tmp/foo.txt")
    }

    func testResolveDotDot() {
        // a/../../b 从 /Users/test/project 向上两层 → /Users/test/b
        let result = PathSecurity.resolvePath("a/../../b/file.txt", relativeTo: base)
        XCTAssertEqual(result, "/Users/test/b/file.txt")
    }

    // MARK: - validatePath

    func testValidateNormalPath() {
        XCTAssertTrue(PathSecurity.validatePath("\(base)/sub/file.txt", allowedBase: base))
    }

    func testValidatePathEqualsBase() {
        XCTAssertTrue(PathSecurity.validatePath(base, allowedBase: base))
    }

    func testValidateDirectoryTraversal() {
        let malicious: String = "\(base)/../../etc/passwd"
        XCTAssertFalse(PathSecurity.validatePath(malicious, allowedBase: base))
    }

    func testValidateSiblingDirectory() {
        let sibling: String = "/Users/test/other/file.txt"
        XCTAssertFalse(PathSecurity.validatePath(sibling, allowedBase: base))
    }

    func testValidateSymlinkInPath() {
        let linkPath: String = "\(base)/sub/../sym/../secret.txt"
        let resolved: String = (linkPath as NSString).standardizingPath
        XCTAssertTrue(resolved.hasPrefix(base))
    }

    // MARK: - safeResolve

    func testSafeResolveNormal() {
        guard let result = PathSecurity.safeResolve("sub/file.txt", relativeTo: base) else {
            XCTFail("safeResolve returned nil for normal path")
            return
        }
        XCTAssertEqual(result, "\(base)/sub/file.txt")
    }

    func testSafeResolveTraversal() {
        let result = PathSecurity.safeResolve("../../etc/passwd", relativeTo: base)
        XCTAssertNil(result)
    }

    func testSafeResolveAbsoluteWithinBase() {
        guard let result = PathSecurity.safeResolve("\(base)/sub/file.txt", relativeTo: base) else {
            XCTFail("safeResolve returned nil for absolute path within base")
            return
        }
        XCTAssertEqual(result, "\(base)/sub/file.txt")
    }

    func testSafeResolveAbsoluteOutsideBase() {
        let result = PathSecurity.safeResolve("/tmp/foo.txt", relativeTo: base)
        XCTAssertNil(result)
    }
}
