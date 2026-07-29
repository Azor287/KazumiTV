import AVFoundation
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

    @MainActor
    func testResolvesAndLoadsLivePlaybackWhenConfigured() async throws {
        guard let pageURL = ProcessInfo.processInfo.environment["KAZUMI_LIVE_PLAYBACK_PAGE_URL"],
              !pageURL.isEmpty else {
            throw XCTSkip("Set KAZUMI_LIVE_PLAYBACK_PAGE_URL to run the real-source playback test")
        }

        let previousValue = SettingsRepository.shared.privateWebResolverEnabled
        SettingsRepository.shared.privateWebResolverEnabled = true
        defer {
            SettingsRepository.shared.privateWebResolverEnabled = previousValue
        }

        try await PluginManager.shared.loadPlugins()
        let loadedPlugin = await PluginManager.shared.getPlugin(name: "AGE")
        let plugin = try XCTUnwrap(loadedPlugin)
        let source = try await VideoSourceResolver.shared.resolveVideoURL(
            pageURL: pageURL,
            plugin: plugin
        )
        XCTAssertTrue(["http", "https"].contains(source.url.scheme?.lowercased() ?? ""))

        let proxiedSource = try LocalHLSProxy.shared.proxiedSource(for: source)
        if proxiedSource.url.host == "127.0.0.1" {
            let (data, response) = try await URLSession.shared.data(from: proxiedSource.url)
            let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
            let playlist = try XCTUnwrap(String(data: data, encoding: .utf8))
            let inspection = HLSPlaylistInspector.inspect(playlist, url: proxiedSource.url)

            XCTAssertEqual(httpResponse.statusCode, 200)
            XCTAssertTrue(inspection.isLikelyPlayable, inspection.reason ?? "playlist is not playable")
        } else {
            XCTAssertEqual(proxiedSource.url, source.url)
            var request = URLRequest(url: source.url)
            request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
            for (name, value) in playbackHeaders(for: source) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
            XCTAssertTrue([200, 206].contains(httpResponse.statusCode))
            XCTAssertFalse(data.isEmpty)
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            XCTAssertTrue(contentType.contains("video") || contentType.contains("octet-stream"))
        }

        let asset = AVURLAsset(
            url: proxiedSource.url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": playbackHeaders(for: proxiedSource),
                "AVURLAssetOutOfBandMIMETypeKey": source.isMP4 ? "video/mp4" : "application/vnd.apple.mpegurl"
            ]
        )
        let isPlayable = try await asset.load(.isPlayable)
        XCTAssertTrue(isPlayable)

        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        player.play()
        try await Task.sleep(nanoseconds: 5_000_000_000)
        XCTAssertGreaterThan(player.currentTime().seconds, 0)
        player.pause()
    }

    private func playbackHeaders(for source: VideoSource) -> [String: String] {
        var headers = source.headers
        if let referer = source.referer, !referer.isEmpty {
            headers["Referer"] = referer
        }
        return headers
    }
}
