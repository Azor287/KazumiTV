//
//  PrivateWebViewResolver.swift
//  KazumiTV
//
//  Local dynamic-page resolver for side-loaded builds. It loads WebKit at
//  runtime and executes pages that cannot be resolved by HTTP parsing alone.
//

import Foundation
import UIKit
import Darwin

#if KAZUMI_ENABLE_PRIVATE_WEBVIEW_RESOLVER
@objc private protocol PrivateWKUserScript {
    init(source: String, injectionTime: Int, forMainFrameOnly: Bool)
}

private enum PrivateWebKitRuntime {
    static let handle = dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_NOW)
}

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
            throw VideoSourceError.privateWebViewFailed("已有本机动态网页解析任务正在运行")
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
    private enum RuntimeKind {
        case wkWebView
        case uiWebView
    }

    private let pageURL: URL
    private let plugin: PluginRule
    private let continuation: CheckedContinuation<VideoSource, Error>
    private let onFinish: () -> Void
    private let timeoutNanoseconds: UInt64 = 30_000_000_000
    private let pollIntervalNanoseconds: UInt64 = 900_000_000

    private var webView: NSObject?
    private var runtimeKind: RuntimeKind?
    private var pollTask: Task<Void, Never>?
    private var validationTask: Task<Void, Never>?
    private var isEvaluatingJavaScript = false
    private var rejectedCandidateURLs = Set<String>()
    private var pendingCandidateValues: [String] = []
    private var visitedNestedPageURLs = Set<String>()
    private var nestedNavigationDepth = 0
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
        let instance: NSObject
        if let wkWebView = makeWKWebView() {
            instance = wkWebView
            runtimeKind = .wkWebView
        } else if let uiWebView = makeUIWebView() {
            instance = uiWebView
            runtimeKind = .uiWebView
        } else {
            complete(.failure(VideoSourceError.privateWebViewUnavailable))
            return
        }

        webView = instance
        guard attachToActiveWindow(instance) else {
            complete(.failure(VideoSourceError.privateWebViewFailed("无法将本机网页运行时挂载到活动窗口")))
            return
        }

        let loadSelector = NSSelectorFromString("loadRequest:")
        guard instance.responds(to: loadSelector) else {
            complete(.failure(VideoSourceError.privateWebViewFailed("本机网页运行时不支持 loadRequest:")))
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

    private func makeWKWebView() -> NSObject? {
        guard PrivateWebKitRuntime.handle != nil else {
            return nil
        }
        guard let webViewClass = NSClassFromString("WKWebView") as? NSObject.Type else {
            return nil
        }

        let instance = webViewClass.init()
        guard let configuration = instance.value(forKey: "configuration") as? NSObject,
              let contentController = configuration.value(forKey: "userContentController") as? NSObject,
              installInterceptionScript(in: contentController) else {
            return nil
        }

        configuration.setValue(true, forKey: "allowsInlineMediaPlayback")
        let setNavigationDelegate = NSSelectorFromString("setNavigationDelegate:")
        guard instance.responds(to: setNavigationDelegate) else {
            return nil
        }
        _ = instance.perform(setNavigationDelegate, with: self)

        let setCustomUserAgent = NSSelectorFromString("setCustomUserAgent:")
        if instance.responds(to: setCustomUserAgent) {
            _ = instance.perform(setCustomUserAgent, with: userAgent)
        }
        return instance
    }

    private func makeUIWebView() -> NSObject? {
        guard let webViewClass = NSClassFromString("UIWebView") as? NSObject.Type else {
            return nil
        }
        let instance = webViewClass.init()
        let setDelegateSelector = NSSelectorFromString("setDelegate:")
        guard instance.responds(to: setDelegateSelector) else {
            return nil
        }
        _ = instance.perform(setDelegateSelector, with: self)
        return instance
    }

    private func installInterceptionScript(in contentController: NSObject) -> Bool {
        guard let userScriptClass = NSClassFromString("WKUserScript") else {
            return false
        }
        let userScriptType = unsafeBitCast(userScriptClass, to: PrivateWKUserScript.Type.self)
        let userScript = userScriptType.init(
            source: interceptionScript(),
            injectionTime: 0,
            forMainFrameOnly: false
        )

        let addUserScript = NSSelectorFromString("addUserScript:")
        let addMessageHandler = NSSelectorFromString("addScriptMessageHandler:name:")
        guard contentController.responds(to: addUserScript),
              contentController.responds(to: addMessageHandler) else {
            return false
        }
        _ = contentController.perform(addUserScript, with: userScript)
        _ = contentController.perform(addMessageHandler, with: self, with: "KazumiMediaIntercept")
        return true
    }

    private func attachToActiveWindow(_ instance: NSObject) -> Bool {
        guard let view = instance as? UIView,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
              let rootView = window.rootViewController?.view else {
            return false
        }

        view.frame = rootView.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        rootView.addSubview(view)
        rootView.sendSubviewToBack(view)
        return true
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

    @objc(userContentController:didReceiveScriptMessage:)
    private func userContentController(_ userContentController: AnyObject, didReceive message: AnyObject) {
        guard !isCompleted, let value = message.value(forKey: "body") as? String else {
            return
        }
        enqueueCandidateValues([value])
    }

    @objc(webView:didFinishNavigation:)
    private func webView(_ webView: AnyObject, didFinish navigation: AnyObject?) {
        attemptExtraction()
        if let webView = webView as? NSObject {
            attemptNestedFrameNavigation(in: webView)
        }
    }

    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    private func webView(
        _ webView: AnyObject,
        decidePolicyFor action: AnyObject,
        decisionHandler: @escaping @convention(block) (Int) -> Void
    ) {
        if let request = action.value(forKey: "request") as? URLRequest,
           let url = request.url {
            enqueueCandidateValues([url.absoluteString])
        }
        decisionHandler(1)
    }

    @objc(webView:didFailProvisionalNavigation:withError:)
    private func webView(_ webView: AnyObject, didFailProvisionalNavigation navigation: AnyObject?, withError error: NSError) {
        handleWKNavigationError(error)
    }

    @objc(webView:didFailNavigation:withError:)
    private func webView(_ webView: AnyObject, didFail navigation: AnyObject?, withError error: NSError) {
        handleWKNavigationError(error)
    }

    private func handleWKNavigationError(_ error: NSError) {
        guard error.code != NSURLErrorCancelled else { return }
        print("PrivateWebViewResolver: WKWebView page load error \(error.localizedDescription)")
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
        guard !isCompleted, let webView else {
            return
        }

        switch runtimeKind {
        case .wkWebView:
            evaluateJavaScriptAsync(extractionScript(), in: webView)
        case .uiWebView:
            guard let json = evaluateJavaScriptSynchronously(extractionScript(), in: webView) else {
                return
            }
            enqueueJSONCandidates(json)
        case .none:
            return
        }
    }

    private func enqueueJSONCandidates(_ json: String) {
        guard let data = json.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return
        }
        enqueueCandidateValues(values)
    }

    private func enqueueCandidateValues(_ values: [String]) {
        guard !isCompleted else { return }
        pendingCandidateValues.append(contentsOf: values)
        validatePendingCandidatesIfNeeded()
    }

    private func validatePendingCandidatesIfNeeded() {
        guard !isCompleted, validationTask == nil, let webView else { return }
        let values = pendingCandidateValues
        pendingCandidateValues.removeAll(keepingCapacity: true)

        let urls = candidateURLs(from: values)
            .filter { !rejectedCandidateURLs.contains($0.absoluteString) }
        guard !urls.isEmpty else { return }

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
                        quality: "本机网页",
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
            self.validatePendingCandidatesIfNeeded()
        }
    }

    private func evaluateJavaScriptSynchronously(_ script: String, in webView: NSObject) -> String? {
        let selector = NSSelectorFromString("stringByEvaluatingJavaScriptFromString:")
        guard webView.responds(to: selector),
              let result = webView.perform(selector, with: script)?.takeUnretainedValue() else {
            return nil
        }
        return result as? String
    }

    private func evaluateJavaScriptAsync(_ script: String, in webView: NSObject) {
        guard !isEvaluatingJavaScript else { return }
        let selector = NSSelectorFromString("evaluateJavaScript:completionHandler:")
        guard webView.responds(to: selector) else { return }

        isEvaluatingJavaScript = true
        let completion: @convention(block) (Any?, Error?) -> Void = { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isEvaluatingJavaScript = false
                if let json = result as? String {
                    self.enqueueJSONCandidates(json)
                }
            }
        }
        _ = webView.perform(selector, with: script, with: completion)
    }

    private func attemptNestedFrameNavigation(in webView: NSObject) {
        guard !isCompleted, nestedNavigationDepth < 3 else { return }
        let selector = NSSelectorFromString("evaluateJavaScript:completionHandler:")
        guard webView.responds(to: selector) else { return }

        let script = """
        (function() {
          var frames = document.querySelectorAll('iframe[src], embed[src]');
          for (var i = 0; i < frames.length; i++) {
            var value = frames[i].src || frames[i].getAttribute('src');
            if (value) return value;
          }
          return '';
        })()
        """
        let completion: @convention(block) (Any?, Error?) -> Void = { [weak self] result, _ in
            Task { @MainActor in
                guard let self,
                      !self.isCompleted,
                      let value = result as? String,
                      let url = URL(string: value, relativeTo: self.pageURL)?.absoluteURL,
                      self.isLikelyNestedPlayerURL(url),
                      !self.visitedNestedPageURLs.contains(url.absoluteString) else {
                    return
                }

                self.visitedNestedPageURLs.insert(url.absoluteString)
                self.nestedNavigationDepth += 1
                let request = NSMutableURLRequest(url: url)
                for (name, value) in self.requestHeaders() where !value.isEmpty {
                    request.setValue(value, forHTTPHeaderField: name)
                }
                _ = webView.perform(NSSelectorFromString("stopLoading"))
                _ = webView.perform(NSSelectorFromString("loadRequest:"), with: request)
            }
        }
        _ = webView.perform(selector, with: script, with: completion)
    }

    private func isLikelyNestedPlayerURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              !isDirectMediaURL(url) else {
            return false
        }
        let value = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        let host = url.host?.lowercased() ?? ""
        return value.contains("url=")
            || path.contains("/vip")
            || path.contains("player")
            || path.contains("parse")
            || path.contains("/jx")
            || host.hasPrefix("jx.")
            || host.contains("player")
    }

    private func candidateURLs(from values: [String]) -> [URL] {
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
        let referer = plugin.referer.flatMap { $0.isEmpty ? nil : $0 } ?? plugin.baseURL
        var headers: [String: String] = [
            "User-Agent": userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Cache-Control": "no-cache",
            "Referer": referer
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
        guard runtimeKind == .uiWebView else { return nil }
        return evaluateJavaScriptSynchronously("document.cookie || ''", in: webView)?
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
        let extensionName = url.pathExtension.lowercased()
        let rejectedExtensions: Set<String> = [
            "js", "css", "html", "htm", "json", "xml",
            "jpg", "jpeg", "png", "gif", "webp", "svg", "ico",
            "woff", "woff2", "ttf", "otf"
        ]
        if rejectedExtensions.contains(extensionName) {
            return false
        }
        if ["mp4", "m4v", "mov", "m4a", "m4s", "ts"].contains(extensionName) {
            return true
        }
        if value.contains("mime_type=video") || value.contains("video_mp4") {
            return true
        }
        let host = url.host?.lowercased() ?? ""
        let hostMarkers = ["toutiao", "byte", "ixigua", "bilivideo", "bcevod", "alicdn", "akamaized", "mgtv"]
        let mediaPathMarkers = ["/video/", "/media/", "/play/", "video_id=", "vid=", "mime=video"]
        return hostMarkers.contains { host.contains($0) }
            && mediaPathMarkers.contains { value.contains($0) || path.contains($0) }
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

    private func interceptionScript() -> String {
        """
        (function() {
          if (window.__KazumiMediaInterceptInstalled) return;
          window.__KazumiMediaInterceptInstalled = true;
          function post(value) {
            if (!value) return;
            try {
              var raw = typeof value === 'string' ? value : (value.url || value.href || String(value));
              if (raw) window.webkit.messageHandlers.KazumiMediaIntercept.postMessage(raw);
            } catch (_) {}
          }
          var originalFetch = window.fetch;
          if (originalFetch) {
            window.fetch = function() {
              post(arguments[0]);
              return originalFetch.apply(this, arguments);
            };
          }
          var originalOpen = XMLHttpRequest.prototype.open;
          XMLHttpRequest.prototype.open = function(method, url) {
            post(url);
            return originalOpen.apply(this, arguments);
          };
          var originalSetAttribute = Element.prototype.setAttribute;
          Element.prototype.setAttribute = function(name, value) {
            if (name === 'src' || name === 'href') post(value);
            return originalSetAttribute.apply(this, arguments);
          };
          function hookSource(proto) {
            if (!proto) return;
            var descriptor = Object.getOwnPropertyDescriptor(proto, 'src');
            if (!descriptor || !descriptor.set) return;
            Object.defineProperty(proto, 'src', {
              configurable: true,
              enumerable: descriptor.enumerable,
              get: descriptor.get ? function() { return descriptor.get.call(this); } : function() { return this.getAttribute('src'); },
              set: function(value) {
                post(value);
                descriptor.set.call(this, value);
              }
            });
          }
          hookSource(typeof HTMLMediaElement !== 'undefined' ? HTMLMediaElement.prototype : null);
          hookSource(typeof HTMLSourceElement !== 'undefined' ? HTMLSourceElement.prototype : null);
          hookSource(typeof HTMLIFrameElement !== 'undefined' ? HTMLIFrameElement.prototype : null);
        })();
        """
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
        isEvaluatingJavaScript = false
        pendingCandidateValues.removeAll()
        let retiringWebView = webView
        if let webView = retiringWebView {
            let stopLoading = NSSelectorFromString("stopLoading")
            if webView.responds(to: stopLoading) {
                _ = webView.perform(stopLoading)
            }

            switch runtimeKind {
            case .wkWebView:
                let setNavigationDelegate = NSSelectorFromString("setNavigationDelegate:")
                if webView.responds(to: setNavigationDelegate) {
                    _ = webView.perform(setNavigationDelegate, with: nil)
                }
                if let configuration = webView.value(forKey: "configuration") as? NSObject,
                   let contentController = configuration.value(forKey: "userContentController") as? NSObject {
                    let removeHandler = NSSelectorFromString("removeScriptMessageHandlerForName:")
                    if contentController.responds(to: removeHandler) {
                        _ = contentController.perform(removeHandler, with: "KazumiMediaIntercept")
                    }
                    let removeAllScripts = NSSelectorFromString("removeAllUserScripts")
                    if contentController.responds(to: removeAllScripts) {
                        _ = contentController.perform(removeAllScripts)
                    }
                }
            case .uiWebView:
                let setDelegate = NSSelectorFromString("setDelegate:")
                if webView.responds(to: setDelegate) {
                    _ = webView.perform(setDelegate, with: nil)
                }
            case .none:
                break
            }
        }
        (retiringWebView as? UIView)?.removeFromSuperview()
        webView = nil
        if runtimeKind == .wkWebView, let retiringWebView {
            PrivateWebViewDrainPool.shared.retire(retiringWebView)
        }
        runtimeKind = nil
        onFinish()
        continuation.resume(with: result)
    }
}

@MainActor
private final class PrivateWebViewDrainPool {
    static let shared = PrivateWebViewDrainPool()

    private let retirementDelayNanoseconds: UInt64 = 1_000_000_000
    private var retiringViews: [ObjectIdentifier: NSObject] = [:]

    private init() {}

    func retire(_ webView: NSObject) {
        let key = ObjectIdentifier(webView)
        retiringViews[key] = webView
        let loadBlank = NSSelectorFromString("loadHTMLString:baseURL:")
        if webView.responds(to: loadBlank) {
            _ = webView.perform(loadBlank, with: "", with: nil)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.retirementDelayNanoseconds)
            guard let webView = self.retiringViews[key] else { return }
            let stopLoading = NSSelectorFromString("stopLoading")
            if webView.responds(to: stopLoading) {
                _ = webView.perform(stopLoading)
            }
            self.retiringViews.removeValue(forKey: key)
        }
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
                  isLikelyMediaResponse(httpResponse, url: url) else {
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

    private static func isLikelyMediaResponse(_ response: HTTPURLResponse, url: URL) -> Bool {
        let contentType = (response.value(forHTTPHeaderField: "Content-Type") ?? "")
            .lowercased()
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        if contentType.hasPrefix("video/")
            || contentType.hasPrefix("audio/")
            || contentType.contains("mpegurl")
            || contentType == "application/octet-stream" {
            return true
        }
        if response.statusCode == 206
            || response.value(forHTTPHeaderField: "Content-Range") != nil {
            return true
        }
        let extensionName = url.pathExtension.lowercased()
        return ["mp4", "m4v", "mov", "m4a", "m4s", "ts"].contains(extensionName)
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
