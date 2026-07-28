//
//  VideoScraper.swift
//  KazumiTV
//
//  Video URL extraction using JavaScriptCore + HTTP parsing
//  Works on tvOS without WKWebView
//

import Foundation
import JavaScriptCore

actor VideoScraper {
    static let shared = VideoScraper()

    private init() {}

    // MARK: - Extract Video URL

    /// Extract video URL from a page
    func extractVideoURL(from pageURL: String, plugin: PluginRule) async throws -> URL {
        // First try direct HTML parsing
        if let directURL = try? await extractDirectURL(from: pageURL, plugin: plugin) {
            return directURL
        }

        // Then try JavaScriptCore for JavaScript-based extraction
        if let jsURL = try? await extractViaJavaScript(from: pageURL, plugin: plugin) {
            return jsURL
        }

        throw VideoSourceError.videoSourceNotFound
    }

    // MARK: - Direct URL Extraction

    private func extractDirectURL(from pageURL: String, plugin: PluginRule) async throws -> URL {
        let api = APIClient.shared

        guard let url = URL(string: pageURL) else {
            throw VideoSourceError.invalidURL
        }

        var headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.15.3 (KHTML, like Gecko) Version/17.0 Safari/605.15.3",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
        ]

        if let referer = plugin.referer {
            headers["Referer"] = referer
        }

        let html = try await api.fetchHTML(url: url, headers: headers)

        // Try to find m3u8 URLs in the HTML
        if let m3u8URL = findM3U8URL(in: html, baseURL: url) {
            return m3u8URL
        }

        // Try to find player iframe and extract from there
        if let playerURL = findPlayerURL(in: html, baseURL: url) {
            return try await extractDirectURL(from: playerURL.absoluteString, plugin: plugin)
        }

        throw VideoSourceError.videoSourceNotFound
    }

    // MARK: - JavaScriptCore Extraction

    private func extractViaJavaScript(from pageURL: String, plugin: PluginRule) async throws -> URL {
        guard let url = URL(string: pageURL) else {
            throw VideoSourceError.invalidURL
        }

        // Fetch the page content
        let api = APIClient.shared
        let html = try await api.fetchHTML(url: url, headers: [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.15.3 (KHTML, like Gecko) Version/17.0 Safari/605.15.3"
        ])

        // Try to find JavaScript that generates video URLs
        for pattern in defaultJSPatterns {
            if let jsCode = extractJavaScriptBlock(from: html, pattern: pattern),
               let videoURL = evaluateJavaScript(jsCode, baseURL: url) {
                if videoURL.contains(".m3u8") || videoURL.contains(".mp4") {
                    return URL(string: videoURL)!
                }
            }
        }

        throw VideoSourceError.javascriptExtractionFailed
    }

    private var defaultJSPatterns: [String] {
        [
            #"player\.src\s*\(\s*["']([^"']+)["']"#,
            #"video\s*\(\s*["']([^"']+)["']"#,
            #"\.play\s*\(\s*["']([^"']+)["']"#,
            #"sources\s*:\s*\[\s*\{[^}]*url\s*:\s*["']([^"']+)["']"#,
            #"url\s*:\s*["']([^"']+\.m3u8[^"']*)["']"#,
            #"playUrl\s*:\s*["']([^"']+)["']"#,
            #"videoUrl\s*:\s*["']([^"']+)["']"#
        ]
    }

    private func extractJavaScriptBlock(from html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(html.startIndex..., in: html)
        if let match = regex.firstMatch(in: html, options: [], range: range),
           match.numberOfRanges > 1,
           let captureRange = Range(match.range(at: 1), in: html) {
            return String(html[captureRange])
        }

        return nil
    }

    private func evaluateJavaScript(_ jsCode: String, baseURL: URL) -> String? {
        guard let context = JSContext() else {
            return nil
        }

        // Set up a minimal console to prevent crashes
        context.exceptionHandler = { _, exception in
            print("JS Error: \(exception?.toString() ?? "unknown")")
        }

        // Create a mock document object for common patterns
        context.evaluateScript("""
            var document = {
                URL: '\(baseURL.absoluteString)',
                cookie: '',
                querySelector: function() { return null; }
            };
            var location = { href: '\(baseURL.absoluteString)', protocol: '\(baseURL.scheme ?? "https")' };
            var navigator = { userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.15.3' };
            var window = { location: location, document: document, navigator: navigator };
        """)

        // Evaluate the extracted JavaScript
        if let result = context.evaluateScript(jsCode), result.isString {
            return result.toString()
        }

        // Try to extract URL from common patterns
        let urlPatterns = [
            #"(https?://[^"'\s]+\.m3u8[^"'\s]*)"#,
            #"(https?://[^"'\s]+\.mp4[^"'\s]*)"#
        ]

        for pattern in urlPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: jsCode, options: [], range: NSRange(jsCode.startIndex..., in: jsCode)),
               let range = Range(match.range(at: 1), in: jsCode) {
                return String(jsCode[range])
            }
        }

        return nil
    }

    // MARK: - URL Finding

    private func findM3U8URL(in html: String, baseURL: URL) -> URL? {
        let patterns = [
            #"src=["']([^"']+\.m3u8[^"']*)["']"#,
            #"url\s*:\s*["']([^"']+\.m3u8[^"']*)["']"#,
            #"https?://[^"'\s]+\.m3u8[^"'\s]*"#,
            #"//[^"'\s]+\.m3u8[^"'\s]*"#
        ]

        for pattern in patterns {
            if let url = matchURL(in: html, pattern: pattern, baseURL: baseURL) {
                return url
            }
        }

        return nil
    }

    private func findPlayerURL(in html: String, baseURL: URL) -> URL? {
        let patterns = [
            #"<iframe[^>]+src=["']([^"']+)["']"#,
            #"<embed[^>]+src=["']([^"']+)["']"#,
            #"player\.load\s*\(\s*["']([^"']+)["']"#
        ]

        for pattern in patterns {
            if let urlString = matchString(in: html, pattern: pattern) {
                let fullURLString = resolveURL(urlString, baseURL: baseURL)
                if isVideoPageURL(fullURLString) {
                    return URL(string: fullURLString)
                }
            }
        }

        return nil
    }

    private func matchURL(in text: String, pattern: String, baseURL: URL) -> URL? {
        guard let string = matchString(in: text, pattern: pattern) else {
            return nil
        }
        let resolved = resolveURL(string, baseURL: baseURL)
        return URL(string: resolved)
    }

    private func matchString(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           match.numberOfRanges > 1,
           let captureRange = Range(match.range(at: 1), in: text) {
            return String(text[captureRange])
        }

        return nil
    }

    private func resolveURL(_ urlString: String, baseURL: URL) -> String {
        if urlString.hasPrefix("http") {
            return urlString
        }
        if urlString.hasPrefix("//") {
            return (baseURL.scheme ?? "https") + ":" + urlString
        }
        if urlString.hasPrefix("/") {
            var components = URLComponents()
            components.scheme = baseURL.scheme
            components.host = baseURL.host
            components.path = urlString
            return components.url?.absoluteString ?? urlString
        }
        return baseURL.deletingLastPathComponent().appendingPathComponent(urlString).absoluteString
    }

    private func isVideoPageURL(_ urlString: String) -> Bool {
        let videoExtensions = ["m3u8", "mp4", "flv", "webm", "avi", "mkv"]
        let lowercased = urlString.lowercased()
        for ext in videoExtensions {
            if lowercased.contains(".\(ext)") {
                return true
            }
        }

        let videoKeywords = ["player", "video", "embed", "play", "watch", "stream"]
        for keyword in videoKeywords {
            if lowercased.contains(keyword) {
                return true
            }
        }

        return false
    }
}

// MARK: - Video Source Error

enum VideoSourceError: LocalizedError {
    case invalidURL
    case javascriptExtractionFailed
    case extractionFailed
    case videoSourceNotFound
    case webViewRequired
    case timeout
    case cancelled
    case emptyHTML
    case challengePage(vendor: String?)
    case captchaRequired(vendor: String?)
    case jsRenderedOnly
    case privateWebViewUnavailable
    case privateWebViewFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .javascriptExtractionFailed:
            return "JavaScript 提取失败 - 可能在 tvOS 上不支持"
        case .extractionFailed:
            return "提取视频 URL 失败"
        case .videoSourceNotFound:
            return "未找到视频源"
        case .webViewRequired:
            return "此来源需要动态网页解析，请在设置中启用。"
        case .timeout:
            return "视频提取超时"
        case .cancelled:
            return "视频提取已取消"
        case .emptyHTML:
            return "来源返回空页面，可能被站点拦截或规则已失效。"
        case .challengePage(let vendor):
            let name = vendor ?? "该来源"
            return "\(name) 正在要求真实浏览器安全验证，Apple TV 本机模式不支持。"
        case .captchaRequired(let vendor):
            let name = vendor ?? "该来源"
            return "\(name) 正在要求验证码验证，Apple TV 本机模式不会自动处理验证码。"
        case .jsRenderedOnly:
            return "该来源需要网页前端渲染后才能获得播放地址，请启用本机动态网页解析。"
        case .privateWebViewUnavailable:
            return "本机动态网页解析在当前系统上不可用。"
        case .privateWebViewFailed(let message):
            return message.isEmpty ? "本机动态网页解析失败。" : "本机动态网页解析失败：\(message)"
        }
    }
}
