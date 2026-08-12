//
//  VideoWebViewManager.swift
//  KazumiTV
//
//  Legacy direct HTTP video URL extraction.
//  The primary playback path now uses NativeVideoResolver and the local
//  private WebKit runtime when a dynamic page is required.
//

import Foundation

actor VideoWebViewManager {
    static let shared = VideoWebViewManager()

    private init() {}

    // MARK: - Extract Video URL

    /// Extract video URL from a page using HTTP requests
    /// Note: This is a simplified version. Full implementation would require
    /// server-side parsing or a proxy approach on tvOS since WKWebView is not available.
    func extractVideoURL(from pageURL: String, plugin: PluginRule) async throws -> URL {
        let api = APIClient.shared

        guard let url = URL(string: pageURL) else {
            throw VideoSourceError.extractionFailed
        }

        var headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.15.3 (KHTML, like Gecko) Version/17.0 Safari/605.15.3"
        ]

        if let referer = plugin.referer {
            headers["Referer"] = referer
        }

        // Try to fetch the page and extract video URL directly
        let html = try await api.fetchHTML(url: url, headers: headers)

        // Try to find M3U8 URL in the HTML
        if let m3u8URL = findM3U8URL(in: html) {
            return URL(string: m3u8URL)!
        }

        // If direct extraction fails and the rule allows dynamic page parsing,
        // let the primary resolver handle the local WebKit fallback.
        if plugin.useWebview {
            throw VideoSourceError.webViewRequired
        }

        throw VideoSourceError.videoSourceNotFound
    }

    // MARK: - URL Finding

    private func findM3U8URL(in html: String) -> String? {
        // Pattern 1: Direct M3U8 in src attribute
        let patterns = [
            #"src=["']([^"']+\.m3u8[^"']*)["']"#,
            #"url\s*:\s*["']([^"']+\.m3u8[^"']*)["']"#,
            #"https?://[^"'\s]+\.m3u8[^"'\s]*"#,
            #"//[^"'\s]+\.m3u8[^"'\s]*"#
        ]

        for pattern in patterns {
            if let url = matchURL(in: html, pattern: pattern) {
                return url
            }
        }

        // Pattern 2: Look for video player embed codes
        if let playerURL = findPlayerURL(in: html) {
            return playerURL
        }

        return nil
    }

    private func matchURL(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range) {
            if match.numberOfRanges > 1,
               let captureRange = Range(match.range(at: 1), in: text) {
                return String(text[captureRange])
            }
        }
        return nil
    }

    private func findPlayerURL(in html: String) -> String? {
        // Look for common video player patterns
        let playerPatterns = [
            #"<video[^>]+src=["']([^"']+)["']"#,
            #"<source[^>]+src=["']([^"']+\.m3u8[^"']*)["']"#,
            #"player\.src\s*\(\s*["']([^"']+)["']"#,
            #"video\s*\(\s*["']([^"']+)["']"#
        ]

        for pattern in playerPatterns {
            if let url = matchURL(in: html, pattern: pattern) {
                if url.contains(".m3u8") || url.contains(".mp4") {
                    return url
                }
            }
        }

        return nil
    }

    // MARK: - Preflight Check

    /// Check whether this legacy direct parser can handle the rule without a
    /// dynamic page runtime.
    func isPluginCompatible(_ plugin: PluginRule) -> Bool {
        return !plugin.useWebview
    }
}
