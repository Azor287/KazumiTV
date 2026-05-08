//
//  VideoSourceResolver.swift
//  KazumiTV
//
//  Video Source Resolver - resolves video URLs from plugin pages
//  使用服务器代理解决 tvOS 无法执行 JavaScript 的问题
//

import Foundation

actor VideoSourceResolver {
    static let shared = VideoSourceResolver()

    /// 是否优先使用服务器代理 (从设置中读取)
    var preferServerProxy: Bool {
        SettingsRepository.shared.serverProxyEnabled
    }

    private init() {}

    // MARK: - Resolve Video URL

    /// Resolve video URL from a page using a plugin
    func resolveVideoURL(pageURL: String, plugin: PluginRule) async throws -> VideoSource {
        print("VideoSourceResolver: 开始解析视频URL: \(pageURL), 插件: \(plugin.name)")
        // 首先尝试使用服务器代理
        if preferServerProxy {
            print("VideoSourceResolver: 优先使用服务器代理")
            do {
                let videoSource = try await resolveWithServer(pageURL: pageURL, plugin: plugin)
                print("VideoSourceResolver: 服务器代理解析成功: \(videoSource.url)")
                return videoSource
            } catch {
                print("VideoSourceResolver: 服务器代理解析失败: \(error)")
                // 服务器不可用，打印警告但继续尝试其他方法
                print("VideoSourceResolver: 服务器代理不可用，尝试本地解析...")
            }
        }

        // 对于非 webview 插件，尝试直接解析
        guard plugin.useWebview else {
            print("VideoSourceResolver: 插件不需要WebView，尝试直接解析")
            return try await resolveDirectVideoURL(pageURL: pageURL, plugin: plugin)
        }

        // 对于需要 webview 的插件，使用 JavaScriptCore
        print("VideoSourceResolver: 插件需要WebView，使用JavaScriptCore解析")
        return try await resolveWithJavaScriptCore(pageURL: pageURL, plugin: plugin)
    }

    // MARK: - 服务器代理解析

    /// 使用服务器代理解析视频 URL
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
