import XCTest
@testable import KazumiTV

final class URLLogSanitizerTests: XCTestCase {
    func testRedactsQueryAndFragment() {
        let redacted = URLLogSanitizer.redacted(
            "https://cdn.example.com/video.m3u8?token=secret#fragment"
        )

        XCTAssertEqual(
            redacted,
            "https://cdn.example.com/video.m3u8?redacted#redacted"
        )
    }

    func testKeepsURLWithoutSensitiveComponents() {
        let value = "https://cdn.example.com/video.m3u8"
        XCTAssertEqual(URLLogSanitizer.redacted(value), value)
    }
}
