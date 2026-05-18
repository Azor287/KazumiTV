//
//  PrivateWebViewResolver.swift
//  KazumiTV
//
//  Experimental resolver for side-loaded builds. It uses a private tvOS
//  UIWebView class when present, so this path must stay optional.
//

import Foundation
import UIKit

#if KAZUMI_ENABLE_PRIVATE_WEBVIEW_RESOLVER
@MainActor
final class PrivateWebViewResolver {
    static let shared = PrivateWebViewResolver()
    static let isCompiled = true

    private var activeResolution: PrivateWebViewResolution?

    private init() {}

    func resolveVideoURL(pageURL: String, plugin: PluginRule) async throws -> VideoSource {
        guard SettingsRepository.shared.privateWebResolverEnabled else {
            throw VideoSourceError.privateWebViewUnavailable
        }
        guard activeResolution == nil else {
            throw VideoSourceError.privateWebViewFailed("已有私有 WebView 解析任务正在运行")
        }
        guard let url = URL(string: pageURL) else {
            throw VideoSourceError.invalidURL
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let resolution = PrivateWebViewResolution(
                    pageURL: url,
                    plugin: plugin,
                    continuation: continuation,
                    onFinish: { [weak self] in
                        self?.activeResolution = nil
                    }
                )
                activeResolution = resolution
                resolution.start()
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.activeResolution?.cancel()
            }
        }
    }
}

@MainActor
private final class PrivateWebViewResolution: NSObject {
    private let pageURL: URL
    private let plugin: PluginRule
    private let continuation: CheckedContinuation<VideoSource, Error>
    private let onFinish: () -> Void
    private let timeoutNanoseconds: UInt64 = 14_000_000_000
    private let pollIntervalNanoseconds: UInt64 = 900_000_000

    private var webView: NSObject?
    private var pollTask: Task<Void, Never>?
    private var validationTask: Task<Void, Never>?
    private var rejectedCandidateURLs = Set<String>()
    private var isCompleted = false

    init(
        pageURL: URL,
        plugin: PluginRule,
        continuation: CheckedContinuation<VideoSource, Error>,
        onFinish: @escaping () -> Void
    ) {
        self.pageURL = pageURL
        self.plugin = plugin
        self.continuation = continuation
        self.onFinish = onFinish
    }

    func start() {
        guard let webViewClass = NSClassFromString("UIWebView") as? NSObject.Type else {
            complete(.failure(VideoSourceError.privateWebViewUnavailable))
            return
        }

        let instance = webViewClass.init()
        guard let view = instance as? UIView else {
            complete(.failure(VideoSourceError.privateWebViewFailed("UIWebView 私有类不是 UIView")))
            return
        }

        webView = instance
        view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        view.alpha = 0.01
        view.isUserInteractionEnabled = false

        let setDelegateSelector = NSSelectorFromString("setDelegate:")
        if instance.responds(to: setDelegateSelector) {
            _ = instance.perform(setDelegateSelector, with: self)
        }

        let loadSelector = NSSelectorFromString("loadRequest:")
        guard instance.responds(to: loadSelector) else {
            complete(.failure(VideoSourceError.privateWebViewFailed("UIWebView 不支持 loadRequest:")))
            return
        }

        let request = NSMutableURLRequest(url: pageURL)
        request.httpMethod = "GET"
        for (name, value) in requestHeaders() where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }
        _ = instance.perform(loadSelector, with: request)
        startPolling()
    }

    func cancel() {
        complete(.failure(CancellationError()))
    }

    @objc private func webViewDidFinishLoad(_ webView: Any) {
        attemptExtraction()
    }

    @objc private func webView(_ webView: Any, didFailLoadWithError error: NSError) {
        if error.code == NSURLErrorCancelled {
            return
        }
        print("PrivateWebViewResolver: page load error \(error.localizedDescription)")
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startedAt = Date()
            while !Task.isCancelled && Date().timeIntervalSince(startedAt) < Double(timeoutNanoseconds) / 1_000_000_000 {
                self.attemptExtraction()
                if self.isCompleted { return }
                try? await Task.sleep(nanoseconds: self.pollIntervalNanoseconds)
            }
            self.complete(.failure(VideoSourceError.privateWebViewFailed("页面执行超时，未发现可播放媒体地址")))
        }
    }

    private func attemptExtraction() {
        guard !isCompleted,
              let webView,
              let json = evaluateJavaScript(extractionScript(), in: webView) else {
            return
        }

        let urls = candidateURLs(from: json)
            .filter { !rejectedCandidateURLs.contains($0.absoluteString) }
        guard !urls.isEmpty, validationTask == nil else { return }

        let candidates = urls.map {
            PrivateWebViewCandidate(
                url: $0,
                headers: playbackHeaders(for: $0, webView: webView)
            )
        }
        validationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for candidate in candidates {
                if await PrivateWebViewMediaProbe.isPlayable(url: candidate.url, headers: candidate.headers) {
                    let source = VideoSource(
                        url: candidate.url,
                        quality: "私有WebView",
                        pluginName: self.plugin.name,
                        referer: self.pageURL.absoluteString,
                        headers: candidate.headers
                    )
                    self.complete(.success(source))
                    return
                }
                self.rejectedCandidateURLs.insert(candidate.url.absoluteString)
            }
            self.validationTask = nil
        }
    }

    private func evaluateJavaScript(_ script: String, in webView: NSObject) -> String? {
        let selector = NSSelectorFromString("stringByEvaluatingJavaScriptFromString:")
        guard webView.responds(to: selector),
              let result = webView.perform(selector, with: script)?.takeUnretainedValue() else {
            return nil
        }
        return result as? String
    }

    private func candidateURLs(from json: String) -> [URL] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }

        var seen = Set<String>()
        var urls: [URL] = []

        for value in values {
            for candidate in expandedCandidateValues(value) {
                guard let url = URL(string: candidate, relativeTo: pageURL)?.absoluteURL,
                      isDirectMediaURL(url),
                      !seen.contains(url.absoluteString) else {
                    continue
                }
                seen.insert(url.absoluteString)
                urls.append(url)
            }
        }

        return urls.sorted { lhs, rhs in
            if isPlaylistURL(lhs) != isPlaylistURL(rhs) {
                return isPlaylistURL(lhs)
            }
            return lhs.absoluteString < rhs.absoluteString
        }
    }

    private func expandedCandidateValues(_ rawValue: String) -> [String] {
        var values: [String] = []
        var seen = Set<String>()

        func add(_ value: String?) {
            guard var value else { return }
            value = normalizeCandidateValue(value)
            guard !value.isEmpty, !seen.contains(value) else { return }
            seen.insert(value)
            values.append(value)
        }

        add(rawValue)
        add(rawValue.removingPercentEncoding)
        if let decoded = base64DecodedString(rawValue) {
            add(decoded)
            add(decoded.removingPercentEncoding)
        }

        return values
    }

    private func normalizeCandidateValue(_ value: String) -> String {
        var result = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
        if result.hasPrefix("//") {
            result = "https:" + result
        }
        return result
    }

    private func base64DecodedString(_ value: String) -> String? {
        var normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while normalized.count % 4 != 0 {
            normalized.append("=")
        }
        guard let data = Data(base64Encoded: normalized) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func requestHeaders() -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Cache-Control": "no-cache",
            "Referer": plugin.referer?.isEmpty == false ? plugin.referer! : plugin.baseURL
        ]
        if let origin = originString(from: headers["Referer"] ?? plugin.baseURL) {
            headers["Origin"] = origin
        }
        return headers
    }

    private func playbackHeaders(for mediaURL: URL, webView: NSObject) -> [String: String] {
        var headers = plugin.playbackHeaders ?? [:]
        headers["User-Agent"] = headers["User-Agent"] ?? userAgent
        headers["Referer"] = headers["Referer"] ?? pageURL.absoluteString
        if headers["Origin"] == nil, let origin = originString(from: pageURL.absoluteString) {
            headers["Origin"] = origin
        }

        if headers["Cookie"] == nil, let cookie = cookieHeader(for: mediaURL) ?? documentCookie(from: webView) {
            headers["Cookie"] = cookie
        }

        return headers
    }

    private var userAgent: String {
        plugin.userAgent.isEmpty
            ? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.15.3 (KHTML, like Gecko) Version/17.0 Safari/605.15.3"
            : plugin.userAgent
    }

    private func documentCookie(from webView: NSObject) -> String? {
        evaluateJavaScript("document.cookie || ''", in: webView)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func cookieHeader(for url: URL) -> String? {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty else {
            return nil
        }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    private func isDirectMediaURL(_ url: URL) -> Bool {
        if isPlaylistURL(url) { return true }
        let value = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        if path.hasSuffix(".mp4") || path.hasSuffix(".m4v") || path.hasSuffix(".mov") {
            return true
        }
        if value.contains("mime_type=video") || value.contains("video_mp4") {
            return true
        }
        let host = url.host?.lowercased() ?? ""
        let hostMarkers = ["toutiao", "byte", "ixigua", "bilivideo", "bcevod", "alicdn", "akamaized", "mgtv"]
        return hostMarkers.contains { host.contains($0) }
    }

    private func isPlaylistURL(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        return value.contains(".m3u8")
            || path.hasSuffix("/manifest")
            || path.hasSuffix("/playlist")
    }

    private func originString(from value: String) -> String? {
        guard let url = URL(string: value),
              let scheme = url.scheme,
              let host = url.host else {
            return nil
        }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private func extractionScript() -> String {
        """
        (function() {
          var hits = [];
          var seen = {};
          function push(value) {
            if (!value) return;
            value = String(value);
            if (!value || seen[value]) return;
            seen[value] = true;
            hits.push(value);
          }
          function pushDecoded(value) {
            push(value);
            try { push(decodeURIComponent(value)); } catch (_) {}
            try { push(unescape(value)); } catch (_) {}
            try { push(atob(value)); } catch (_) {}
          }
          var elements = document.querySelectorAll('video, source, iframe, embed');
          for (var i = 0; i < elements.length; i++) {
            var el = elements[i];
            push(el.currentSrc);
            push(el.src);
            push(el.getAttribute('src'));
            push(el.getAttribute('data-src'));
            push(el.getAttribute('data-url'));
            push(el.getAttribute('data-play'));
            push(el.getAttribute('data-original'));
          }
          var globals = ['player_aaaa', 'player_data', 'MacPlayer', 'player', 'videoObject'];
          for (var g = 0; g < globals.length; g++) {
            try {
              var obj = window[globals[g]];
              if (!obj) continue;
              if (typeof obj === 'string') pushDecoded(obj);
              pushDecoded(obj.url);
              pushDecoded(obj.file);
              pushDecoded(obj.src);
              pushDecoded(obj.playurl);
              pushDecoded(obj.play_url);
              pushDecoded(obj.vurl);
              pushDecoded(obj.PlayUrl);
            } catch (_) {}
          }
          var html = document.documentElement ? document.documentElement.outerHTML : '';
          html.replace(/(?:https?:)?\\/\\/[^"'\\s<>]+?(?:m3u8|mp4|m4v|mov)[^"'\\s<>]*/ig, function(value) {
            pushDecoded(value);
            return value;
          });
          html.replace(/(?:url|file|src|playurl|play_url|videoUrl|video_url)\\s*[:=]\\s*["']([^"']+)["']/ig, function(_, value) {
            pushDecoded(value);
            return value;
          });
          return JSON.stringify(hits);
        })()
        """
    }

    private func complete(_ result: Result<VideoSource, Error>) {
        guard !isCompleted else { return }
        isCompleted = true
        pollTask?.cancel()
        validationTask?.cancel()
        if let webView {
            let setDelegateSelector = NSSelectorFromString("setDelegate:")
            if webView.responds(to: setDelegateSelector) {
                _ = webView.perform(setDelegateSelector, with: nil)
            }
        }
        (webView as? UIView)?.removeFromSuperview()
        webView = nil
        onFinish()
        continuation.resume(with: result)
    }
}
#else
@MainActor
final class PrivateWebViewResolver {
    static let shared = PrivateWebViewResolver()
    static let isCompiled = false

    private init() {}

    func resolveVideoURL(pageURL: String, plugin: PluginRule) async throws -> VideoSource {
        throw VideoSourceError.privateWebViewUnavailable
    }
}
#endif

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct PrivateWebViewCandidate {
    let url: URL
    let headers: [String: String]
}

private enum PrivateWebViewMediaProbe {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }()

    static func isPlayable(url: URL, headers: [String: String]) async -> Bool {
        if isPlaylistURL(url) {
            return await validatePlaylist(url: url, headers: headers)
        }
        return await validateDirectMedia(url: url, headers: headers)
    }

    private static func validatePlaylist(url: URL, headers: [String: String]) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 14
        request.setValue("application/vnd.apple.mpegurl,application/x-mpegURL,*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        for (name, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  WebChallengeDetector.detect(data: data, response: httpResponse) == nil else {
                print("PrivateWebViewResolver: candidate validation failed: \(redactedURLString(url))")
                return false
            }
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            let inspection = HLSPlaylistInspector.inspect(text, url: url)
            if !inspection.isLikelyPlayable {
                print("PrivateWebViewResolver: candidate rejected, \(inspection.reason ?? "unplayable playlist"): \(redactedURLString(url))")
            }
            return inspection.isLikelyPlayable
        } catch {
            print("PrivateWebViewResolver: candidate validation failed: \(redactedURLString(url)), error: \(error.localizedDescription)")
            return false
        }
    }

    private static func validateDirectMedia(url: URL, headers: [String: String]) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        for (name, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (_, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode),
                  !isHTMLLikeContentType(httpResponse) else {
                print("PrivateWebViewResolver: direct candidate validation failed: \(redactedURLString(url))")
                return false
            }
            return true
        } catch {
            print("PrivateWebViewResolver: direct candidate validation failed: \(redactedURLString(url)), error: \(error.localizedDescription)")
            return false
        }
    }

    private static func isPlaylistURL(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        return value.contains(".m3u8")
            || path.hasSuffix("/manifest")
            || path.hasSuffix("/playlist")
    }

    private static func isHTMLLikeContentType(_ response: HTTPURLResponse) -> Bool {
        let contentType = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        return contentType.contains("text/html") || contentType.contains("application/xhtml")
    }

    private static func redactedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.host ?? "unknown"
        }
        components.query = components.queryItems?.isEmpty == false ? "<redacted>" : nil
        components.fragment = nil
        return components.string ?? "\(url.scheme ?? "https")://\(url.host ?? "unknown")\(url.path)"
    }
}
