//
//  VideoSourceResolver.swift
//  KazumiTV
//
//  Video Source Resolver - resolves video URLs from plugin pages.
//  It now prefers native tvOS parsing and uses the external server only as
//  an explicit fallback for sources that require a real browser runtime.
//

import Foundation

actor VideoSourceResolver {
    static let shared = VideoSourceResolver()

    /// 是否启用外部后备解析服务 (从设置中读取)
    var preferServerProxy: Bool {
        SettingsRepository.shared.serverProxyEnabled
    }

    private init() {}

    // MARK: - Resolve Video URL

    /// Resolve video URL from a page using a plugin
    func resolveVideoURL(pageURL: String, plugin: PluginRule) async throws -> VideoSource {
        print("VideoSourceResolver: 开始解析视频URL: \(pageURL), 插件: \(plugin.name)")

        do {
            print("VideoSourceResolver: 优先使用 tvOS 原生解析")
            let videoSource = try await NativeVideoResolver.shared.resolveVideoURL(pageURL: pageURL, plugin: plugin)
            print("VideoSourceResolver: 原生解析成功: \(videoSource.url)")
            return videoSource
        } catch {
            print("VideoSourceResolver: 原生解析失败: \(error)")
            if SettingsRepository.shared.privateWebResolverEnabled {
                do {
                    return try await resolveWithPrivateWebView(pageURL: pageURL, plugin: plugin)
                } catch let privateError {
                    print("VideoSourceResolver: 私有 WebView 解析失败: \(privateError)")
                    if !preferServerProxy {
                        throw localModeError(nativeError: privateError, plugin: plugin)
                    }
                }
            }

            guard preferServerProxy else {
                throw localModeError(nativeError: error, plugin: plugin)
            }

            print("VideoSourceResolver: 尝试外部后备解析服务")
            do {
                let videoSource = try await resolveWithServer(pageURL: pageURL, plugin: plugin)
                print("VideoSourceResolver: 外部后备解析成功: \(videoSource.url)")
                return videoSource
            } catch let serverError {
                print("VideoSourceResolver: 外部后备解析失败: \(serverError)")
                throw serverError
            }
        }
    }

    private func resolveWithPrivateWebView(pageURL: String, plugin: PluginRule) async throws -> VideoSource {
        guard SettingsRepository.shared.privateWebResolverEnabled else {
            throw VideoSourceError.privateWebViewUnavailable
        }

        print("VideoSourceResolver: 尝试实验性私有 WebView 解析")
        let videoSource = try await PrivateWebViewResolver.shared.resolveVideoURL(pageURL: pageURL, plugin: plugin)
        print("VideoSourceResolver: 私有 WebView 解析成功: \(videoSource.url)")
        return videoSource
    }

    // MARK: - 外部后备解析

    /// 使用外部解析服务解析视频 URL
    private func resolveWithServer(pageURL: String, plugin: PluginRule) async throws -> VideoSource {
        print("VideoSourceResolver.resolveWithServer: 开始，pageURL: \(pageURL), plugin: \(plugin.name)")
        let serverAPI = ServerAPI.shared

        // 先检查服务器是否可用
        print("VideoSourceResolver.resolveWithServer: 检查服务器健康状态...")
        let isHealthy = await serverAPI.healthCheck()
        print("VideoSourceResolver.resolveWithServer: 服务器健康状态: \(isHealthy)")
        guard isHealthy else {
            print("VideoSourceResolver.resolveWithServer: 服务器不可用")
            throw VideoSourceError.serverUnavailable
        }

        // 使用服务器抓取视频
        print("VideoSourceResolver.resolveWithServer: 调用 serverAPI.scrapeVideo...")
        let videoSource = try await serverAPI.scrapeVideo(url: pageURL, plugin: plugin.name)
        print("VideoSourceResolver.resolveWithServer: 抓取成功，videoSource.url = \(videoSource.url)")
        return videoSource
    }

    private func localModeError(nativeError error: Error, plugin: PluginRule) -> Error {
        if let sourceError = error as? VideoSourceError {
            switch sourceError {
            case .invalidURL,
                 .challengePage(_),
                 .captchaRequired(_),
                 .jsRenderedOnly,
                 .emptyHTML,
                 .timeout,
                 .cancelled,
                 .privateWebViewUnavailable,
                 .privateWebViewFailed(_):
                return sourceError
            case .videoSourceNotFound where plugin.playbackCapability.requiresBrowserRuntime:
                return VideoSourceError.jsRenderedOnly
            default:
                return VideoSourceError.externalResolverRequired
            }
        }

        if let apiError = error as? APIError,
           case .webChallenge(let signal) = apiError {
            switch signal.kind {
            case .challenge:
                return VideoSourceError.challengePage(vendor: signal.vendor)
            case .captcha:
                return VideoSourceError.captchaRequired(vendor: signal.vendor)
            }
        }

        return VideoSourceError.externalResolverRequired
    }

    // MARK: - Direct Resolution

    private func resolveDirectVideoURL(pageURL: String, plugin: PluginRule) async throws -> VideoSource {
        let api = APIClient.shared

        guard let url = URL(string: pageURL) else {
            throw PluginError.invalidURL(pageURL)
        }

        var headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.15.3 (KHTML, like Gecko) Version/17.0 Safari/605.15.3"
        ]

        if let referer = plugin.referer {
            headers["Referer"] = referer
        }

        let html = try await api.fetchHTML(url: url, headers: headers)

        // Try to find video URLs in the HTML
        if let m3u8URL = findM3U8URL(in: html) {
            return VideoSource(
                url: URL(string: m3u8URL)!,
                quality: "默认",
                pluginName: plugin.name,
                referer: pageURL,
                headers: headers
            )
        }

        throw PluginError.videoSourceNotFound
    }

    private func findM3U8URL(in html: String) -> String? {
        // Look for m3u8 URLs in script tags
        let patterns = [
            #"src="([^"]+\.m3u8[^"]*)""#,
            #"url\s*:\s*["']([^"']+\.m3u8[^"']*)["']"#,
            #"https?://[^"'\s]+\.m3u8[^"'\s]*"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range])
            }
        }

        return nil
    }

    // MARK: - JavaScriptCore Resolution

    /// 使用 JavaScriptCore 解析视频 URL（tvOS 备用方案）
    private func resolveWithJavaScriptCore(pageURL: String, plugin: PluginRule) async throws -> VideoSource {
        let scraper = VideoScraper.shared
        let url = try await scraper.extractVideoURL(from: pageURL, plugin: plugin)
        return VideoSource(
            url: url,
            quality: "默认",
            pluginName: plugin.name,
            referer: pageURL
        )
    }
}
