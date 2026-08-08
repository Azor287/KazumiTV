import AVFoundation
import XCTest
@testable import KazumiTV

final class AllRulesLiveMatrixTests: XCTestCase {
    @MainActor
    func testMXdm() async throws { try await assertRule("MXdm") }
    @MainActor
    func testOmofun03() async throws { try await assertRule("omofun03") }
    @MainActor
    func testBaimao() async throws { try await assertRule("baimao") }
    @MainActor
    func testEnlie() async throws { try await assertRule("enlie") }
    @MainActor
    func testGpjda() async throws { try await assertRule("gpjda") }
    @MainActor
    func testAafun() async throws { try await assertRule("aafun") }
    @MainActor
    func testMwcy() async throws { try await assertRule("mwcy") }
    @MainActor
    func testGugu3() async throws { try await assertRule("gugu3") }
    @MainActor
    func test7sefun() async throws { try await assertRule("7sefun") }
    @MainActor
    func testYishijie() async throws { try await assertRule("yishijie") }
    @MainActor
    func testDM84() async throws { try await assertRule("DM84") }
    @MainActor
    func testAGE() async throws { try await assertRule("AGE") }
    @MainActor
    func testXfdmneo() async throws { try await assertRule("xfdmneo") }
    @MainActor
    func testTvTFun() async throws { try await assertRule("TvTFun") }
    @MainActor
    func testSorani() async throws { try await assertRule("sorani") }
    @MainActor
    func testDalvdm() async throws { try await assertRule("dalvdm") }
    @MainActor
    func testGiriGiriLove() async throws { try await assertRule("giriGiriLove") }
    @MainActor
    func testFcdm() async throws { try await assertRule("fcdm") }
    @MainActor
    func testMgnacg() async throws { try await assertRule("mgnacg") }
    @MainActor
    func testMutefun() async throws { try await assertRule("mutefun") }
    @MainActor
    func testXfdm() async throws { try await assertRule("xfdm") }

    @MainActor
    private func assertRule(_ name: String) async throws {
        guard ProcessInfo.processInfo.environment["KAZUMI_RUN_ALL_RULES_LIVE"] == "1" else {
            throw XCTSkip("Set KAZUMI_RUN_ALL_RULES_LIVE=1 in the test process to run the live rule matrix")
        }

        let keyword = ProcessInfo.processInfo.environment["KAZUMI_RULE_TEST_KEYWORD"] ?? "海贼王"
        let previousPrivateResolverValue = SettingsRepository.shared.privateWebResolverEnabled
        SettingsRepository.shared.privateWebResolverEnabled = true
        defer {
            SettingsRepository.shared.privateWebResolverEnabled = previousPrivateResolverValue
        }

        try await PluginManager.shared.loadPlugins()
        let report = await exerciseRule(named: name, keyword: keyword)
        print(report.logLine)
        XCTAssertTrue(report.passed, report.failure ?? "\(name) did not pass")
    }

    @MainActor
    private func exerciseRule(named name: String, keyword: String) async -> RuleReport {
        do {
            let downloadedRule = try await downloadRule(named: name)
            try await PluginManager.shared.upsertPlugin(downloadedRule)
            guard let plugin = await PluginManager.shared.getPlugin(name: name) else {
                return RuleReport(name: name, failure: "规则安装后未加载")
            }

            let searchResults = try await PluginManager.shared.searchWithPlugin(
                plugin: plugin,
                keyword: keyword
            )
            let candidates = prioritizedResults(from: searchResults, keyword: keyword)
            guard !candidates.isEmpty else {
                return RuleReport(
                    name: name,
                    searchCount: searchResults.count,
                    failure: "搜索结果为空"
                )
            }

            var selectedResult: SearchItem?
            var roads: [ChapterRoad] = []
            for candidate in candidates.prefix(8) {
                do {
                    let candidateRoads = try await PluginManager.shared.getChapters(
                        pageURL: candidate.src,
                        plugin: plugin
                    )
                    guard !candidateRoads.isEmpty else { continue }
                    selectedResult = candidate
                    roads = candidateRoads
                    break
                } catch {
                    continue
                }
            }
            guard !roads.isEmpty else {
                return RuleReport(
                    name: name,
                    searchCount: searchResults.count,
                    failure: "详情页没有解析出播放线路"
                )
            }
            if let selectedResult {
                print(
                    "RULE_MATRIX_SELECTED|name=\(name)"
                        + "|title=\(selectedResult.displayName)"
                        + "|url=\(selectedResult.src)"
                )
            }

            var roadFailures: [String] = []
            var playableRoadCount = 0
            let roadsToTest = roads
            for road in roadsToTest {
                guard let episode = road.episodes.last else {
                    roadFailures.append("\(road.name): 没有集数")
                    continue
                }

                do {
                    let source = try await VideoSourceResolver.shared.resolveVideoURL(
                        pageURL: episode.src,
                        plugin: plugin
                    )
                    try await verifyActualPlayback(source: source)
                    playableRoadCount += 1
                } catch {
                    roadFailures.append("\(road.name): \(error.localizedDescription)")
                }
            }

            return RuleReport(
                name: name,
                searchCount: searchResults.count,
                roadCount: roads.count,
                testedRoadCount: roadsToTest.count,
                playableRoadCount: playableRoadCount,
                failure: roadFailures.isEmpty ? nil : roadFailures.joined(separator: "；")
            )
        } catch {
            return RuleReport(name: name, failure: error.localizedDescription)
        }
    }

    private func downloadRule(named name: String) async throws -> PluginRule {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let baseURLs = [
            "https://raw.githubusercontent.com/Predidit/KazumiRules/main/",
            "https://cdn.jsdelivr.net/gh/Predidit/KazumiRules@main/",
        ]
        var failures: [String] = []

        for baseURL in baseURLs {
            guard let url = URL(string: "\(baseURL)\(encodedName).json") else { continue }
            for attempt in 1...2 {
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 20
                    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw MatrixError.invalidRuleResponse(name: name, status: -1)
                    }
                    guard httpResponse.statusCode == 200 else {
                        throw MatrixError.invalidRuleResponse(
                            name: name,
                            status: httpResponse.statusCode
                        )
                    }
                    return try JSONDecoder().decode(PluginRule.self, from: data)
                } catch {
                    failures.append(
                        "\(url.host ?? baseURL) 第\(attempt)次：\(error.localizedDescription)"
                    )
                    if attempt == 1 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                }
            }
        }

        throw MatrixError.ruleDownloadFailed(
            name: name,
            details: failures.joined(separator: "；")
        )
    }

    private func prioritizedResults(from results: [SearchItem], keyword: String) -> [SearchItem] {
        let exact = results.filter {
            $0.displayName.compare(
                keyword,
                options: [.caseInsensitive, .widthInsensitive],
                locale: .current
            ) == .orderedSame
        }
        let matching = results.filter { result in
            result.displayName.localizedCaseInsensitiveContains(keyword)
                && !exact.contains { $0.src == result.src }
        }
        let remaining = results.filter { result in
            !exact.contains { $0.src == result.src }
                && !matching.contains { $0.src == result.src }
        }
        return exact + matching + remaining
    }

    @MainActor
    private func verifyActualPlayback(source: VideoSource) async throws {
        let playbackSource = try LocalHLSProxy.shared.proxiedSource(for: source)
        if playbackSource.url.host == "127.0.0.1" {
            let (data, response) = try await URLSession.shared.data(from: playbackSource.url)
            let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
            guard httpResponse.statusCode == 200 else {
                throw MatrixError.invalidMediaStatus(httpResponse.statusCode)
            }
            let playlist = try XCTUnwrap(String(data: data, encoding: .utf8))
            let inspection = HLSPlaylistInspector.inspect(playlist, url: playbackSource.url)
            guard inspection.isLikelyPlayable else {
                throw MatrixError.invalidPlaylist(inspection.reason ?? "unknown")
            }
        } else {
            var request = URLRequest(url: playbackSource.url)
            request.timeoutInterval = 20
            request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
            for (name, value) in playbackHeaders(for: playbackSource) {
                request.setValue(value, forHTTPHeaderField: name)
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
            guard [200, 206].contains(httpResponse.statusCode), !data.isEmpty else {
                throw MatrixError.invalidMediaStatus(httpResponse.statusCode)
            }
        }

        let asset = AVURLAsset(
            url: playbackSource.url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": playbackHeaders(for: playbackSource),
                "AVURLAssetOutOfBandMIMETypeKey": source.isMP4
                    ? "video/mp4"
                    : "application/vnd.apple.mpegurl",
            ]
        )
        guard try await asset.load(.isPlayable) else {
            throw MatrixError.assetNotPlayable
        }

        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.isMuted = true
        player.play()
        let deadline = Date().addingTimeInterval(15)
        var elapsed = 0.0
        while Date() < deadline, elapsed <= 0 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            elapsed = player.currentTime().seconds
        }
        player.pause()
        guard elapsed > 0 else {
            throw MatrixError.playbackDidNotAdvance
        }
    }

    private func playbackHeaders(for source: VideoSource) -> [String: String] {
        var headers = source.headers
        if let referer = source.referer, !referer.isEmpty {
            headers["Referer"] = referer
        }
        return headers
    }
}

private struct RuleReport {
    let name: String
    var searchCount = 0
    var roadCount = 0
    var testedRoadCount = 0
    var playableRoadCount = 0
    var failure: String?

    var passed: Bool {
        failure == nil && testedRoadCount > 0 && testedRoadCount == playableRoadCount
    }

    var logLine: String {
        "RULE_MATRIX|name=\(name)"
            + "|search=\(searchCount)"
            + "|roads=\(roadCount)"
            + "|testedRoads=\(testedRoadCount)"
            + "|playableRoads=\(playableRoadCount)"
            + "|status=\(passed ? "PASS" : "FAIL")"
            + "|reason=\(failure ?? "")"
    }
}

private enum MatrixError: LocalizedError {
    case invalidRuleResponse(name: String, status: Int)
    case ruleDownloadFailed(name: String, details: String)
    case invalidMediaStatus(Int)
    case invalidPlaylist(String)
    case assetNotPlayable
    case playbackDidNotAdvance

    var errorDescription: String? {
        switch self {
        case let .invalidRuleResponse(name, status):
            return "\(name) 规则下载 HTTP \(status)"
        case let .ruleDownloadFailed(name, details):
            return "\(name) 规则双源下载失败：\(details)"
        case let .invalidMediaStatus(status):
            return "媒体请求 HTTP \(status)"
        case let .invalidPlaylist(reason):
            return "HLS 不可播放：\(reason)"
        case .assetNotPlayable:
            return "AVFoundation 判定媒体不可播放"
        case .playbackDidNotAdvance:
            return "AVPlayer 启动后播放时间未前进"
        }
    }
}
