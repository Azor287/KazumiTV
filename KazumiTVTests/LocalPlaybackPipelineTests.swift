import XCTest
@testable import KazumiTV

final class LocalPlaybackPipelineTests: XCTestCase {
    func testCookieJarMatchesDomainPathAndSecureRules() throws {
        let jar = MediaCookieJar()
        let origin = try XCTUnwrap(URL(string: "https://media.example.com/video/master.m3u8"))
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: origin,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Set-Cookie": "session=abc123; Domain=.example.com; Path=/video; Secure"
                ]
            )
        )

        jar.storeCookies(from: response, for: origin)

        XCTAssertEqual(
            jar.cookieHeader(for: try XCTUnwrap(URL(string: "https://cdn.example.com/video/segment.ts"))),
            "session=abc123"
        )
        XCTAssertNil(
            jar.cookieHeader(for: try XCTUnwrap(URL(string: "http://cdn.example.com/video/segment.ts")))
        )
        XCTAssertNil(
            jar.cookieHeader(for: try XCTUnwrap(URL(string: "https://cdn.example.com/other/segment.ts")))
        )
        XCTAssertNil(
            jar.cookieHeader(for: try XCTUnwrap(URL(string: "https://cdn.example.com/videographer/segment.ts")))
        )
    }

    func testLoopbackProxyRewritesFixturePlaylistWhenConfigured() async throws {
        guard let upstreamURLString = ProcessInfo.processInfo.environment["KAZUMI_HLS_SMOKE_URL"],
              let upstreamURL = URL(string: upstreamURLString) else {
            throw XCTSkip("Set KAZUMI_HLS_SMOKE_URL to run the loopback proxy smoke test")
        }

        let source = VideoSource(
            url: upstreamURL,
            quality: "测试",
            pluginName: "Fixture",
            referer: upstreamURL.deletingLastPathComponent().appendingPathComponent("index.html").absoluteString,
            headers: ["X-Fixture": "local"]
        )

        let proxiedSource = try LocalHLSProxy.shared.proxiedSource(for: source)
        XCTAssertEqual(proxiedSource.url.host, "127.0.0.1")
        XCTAssertNotEqual(proxiedSource.url, upstreamURL)

        let (data, response) = try await URLSession.shared.data(from: proxiedSource.url)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        let playlist = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertTrue(playlist.contains("#EXTM3U"))
        XCTAssertTrue(playlist.contains("http://127.0.0.1:"))
        XCTAssertTrue(playlist.contains("/media/"))
        XCTAssertFalse(playlist.contains("segment.ts"))
    }
}
