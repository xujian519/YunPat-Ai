import XCTest

@testable import YunPatCore

final class SSRGuardTests: XCTestCase {

    // MARK: - IPv4: Loopback

    func testBlocksLoopbackIPv4() {
        XCTAssertTrue(SSRGuard.isPrivateIPv4("127.0.0.1"))
        XCTAssertTrue(SSRGuard.isPrivateIPv4("127.255.255.255"))
    }

    // MARK: - IPv4: RFC1918

    func testBlocksRFC1918() {
        // Class A: 10.0.0.0/8
        XCTAssertTrue(SSRGuard.isPrivateIPv4("10.0.0.1"))
        XCTAssertTrue(SSRGuard.isPrivateIPv4("10.255.255.254"))
        // Class B: 172.16.0.0/12
        XCTAssertTrue(SSRGuard.isPrivateIPv4("172.16.0.1"))
        XCTAssertTrue(SSRGuard.isPrivateIPv4("172.31.255.254"))
        // Class C: 192.168.0.0/16
        XCTAssertTrue(SSRGuard.isPrivateIPv4("192.168.1.1"))
        XCTAssertTrue(SSRGuard.isPrivateIPv4("192.168.255.254"))
    }

    // MARK: - IPv4: Link-local

    func testBlocksLinkLocal() {
        XCTAssertTrue(SSRGuard.isPrivateIPv4("169.254.1.1"))
        XCTAssertTrue(SSRGuard.isPrivateIPv4("169.254.255.254"))
    }

    // MARK: - IPv4: Public

    func testAllowsPublicIPv4() {
        XCTAssertFalse(SSRGuard.isPrivateIPv4("8.8.8.8"))
        XCTAssertFalse(SSRGuard.isPrivateIPv4("1.1.1.1"))
    }

    // MARK: - IPv6: Loopback

    func testBlocksLoopbackIPv6() {
        XCTAssertTrue(SSRGuard.isReservedIPv6("::1"))
    }

    // MARK: - IPv6: Link-local

    func testBlocksLinkLocalIPv6() {
        XCTAssertTrue(SSRGuard.isReservedIPv6("fe80::1"))
        XCTAssertTrue(SSRGuard.isReservedIPv6("fe80::abcd:1234:5678:9abc"))
    }

    // MARK: - IPv6: Multicast

    func testBlocksMulticastIPv6() {
        XCTAssertTrue(SSRGuard.isReservedIPv6("ff02::1"))
        XCTAssertTrue(SSRGuard.isReservedIPv6("ff00::1"))
    }

    // MARK: - IPv6: Public

    func testAllowsPublicIPv6() {
        XCTAssertFalse(SSRGuard.isReservedIPv6("2001:4860:4860::8888"))
    }

    // MARK: - Hostname: Metadata / cloud endpoints

    func testBlocksMetadataHostnames() {
        XCTAssertTrue(SSRGuard.isBlockedHostname("169.254.169.254"))
        XCTAssertTrue(SSRGuard.isBlockedHostname("metadata.google.internal"))
        XCTAssertTrue(SSRGuard.isBlockedHostname("metadata"))
    }

    // MARK: - Hostname: .local / .internal suffixes

    func testBlocksDotLocal() {
        XCTAssertTrue(SSRGuard.isBlockedHostname("myhost.local"))
        XCTAssertTrue(SSRGuard.isBlockedHostname("service.internal"))
        XCTAssertTrue(SSRGuard.isBlockedHostname("foo.local"))
    }

    // MARK: - Hostname: Public

    func testAllowsPublicHostnames() {
        XCTAssertFalse(SSRGuard.isBlockedHostname("google.com"))
        XCTAssertFalse(SSRGuard.isBlockedHostname("api.openai.com"))
    }

    // MARK: - checkSSRF: Blocks private

    func testCheckSSRFBlocksPrivate() {
        let result = SSRGuard.checkSSRF("http://127.0.0.1:8080", allowPrivate: false)
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.errorCode, .ssrfBlocked)
    }

    // MARK: - checkSSRF: allowPrivate bypass

    func testCheckSSRFAllowsWithBypass() {
        let result = SSRGuard.checkSSRF("http://127.0.0.1:8080", allowPrivate: true)
        XCTAssertTrue(result.ok)
    }

    // MARK: - checkSSRF: allowPrivate still blocks cloud metadata

    func testCheckSSRFBlocksMetadataEvenWithBypass() {
        let result = SSRGuard.checkSSRF("http://169.254.169.254/latest", allowPrivate: true)
        XCTAssertFalse(result.ok, "Cloud metadata must be blocked even with allowPrivate=true")
        XCTAssertEqual(result.errorCode, .ssrfBlocked)
    }

    // MARK: - checkSSRF: blocks IPv4-mapped IPv6

    func testCheckSSRFBlocksIPv4MappedIPv6() {
        // ::ffff:192.168.1.1 is a mapped private address → should be blocked via IPv6 check
        let result = SSRGuard.checkSSRF("http://[::ffff:192.168.1.1]:80", allowPrivate: false)
        XCTAssertFalse(result.ok)
    }

    // MARK: - checkSSRF: blocks 0.0.0.0

    func testCheckSSRFBlocksZeroAddress() {
        let result = SSRGuard.checkSSRF("http://0.0.0.0:9090", allowPrivate: false)
        XCTAssertFalse(result.ok)
    }

    // MARK: - checkSSRF: blocks FTP scheme

    func testCheckSSRFBlocksFtpScheme() {
        let result = SSRGuard.checkSSRF("ftp://example.com/file", allowPrivate: false)
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.errorCode, .ssrfBlocked)
    }

    // MARK: - checkSSRF: Blocks non-HTTP schemes

    func testCheckSSRFBlocksFileScheme() {
        let result = SSRGuard.checkSSRF("file:///etc/passwd", allowPrivate: false)
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.errorCode, .ssrfBlocked)
    }
}
