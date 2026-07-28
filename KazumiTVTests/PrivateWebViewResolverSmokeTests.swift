import XCTest
@testable import KazumiTV

final class PrivateWebViewResolverSmokeTests: XCTestCase {
    @MainActor
    func testResolvesDynamicallyRequestedPlaylistWhenFixtureIsConfigured() async throws {
        guard let pageURL = ProcessInfo.processInfo.environment["KAZUMI_WEBVIEW_SMOKE_URL"],
              !pageURL.isEmpty else {
            throw XCTSkip("Set KAZUMI_WEBVIEW_SMOKE_URL to run the private WebKit smoke test")
        }

        let previousValue = SettingsRepository.shared.privateWebResolverEnabled
        SettingsRepository.shared.privateWebResolverEnabled = true
        defer {
            SettingsRepository.shared.privateWebResolverEnabled = previousValue
        }
        let source = try await PrivateWebViewResolver.shared.resolveVideoURL(
            pageURL: pageURL,
            plugin: .template()
        )

        XCTAssertTrue(source.url.absoluteString.hasSuffix("/master.m3u8"))
        XCTAssertEqual(source.quality, "本机网页")
    }
}
