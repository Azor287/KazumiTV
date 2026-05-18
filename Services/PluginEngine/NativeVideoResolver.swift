//
//  NativeVideoResolver.swift
//  KazumiTV
//
//  Native video resolver for tvOS. It does not use WebView or Playwright;
//  instead it fetches pages, walks iframe/player pages, and extracts direct
//  m3u8/mp4 URLs that can be handed to the in-app loopback HLS proxy.
//

import Foundation
import CommonCrypto
import Fuzi
import JavaScriptCore

actor NativeVideoResolver {
    static let shared = NativeVideoResolver()

    private let maxDepth = 3
    private let defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
    private let validationSession: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.connectionProxyDictionary = [:]
        validationSession = URLSession(configuration: configuration)
    }

    func resolveVideoURL(pageURL: String, plugin: PluginRule) async throws -> VideoSource {
        guard let rootURL = URL(string: normalizedURLString(pageURL, baseURL: plugin.baseURL)) else {
            throw VideoSourceError.invalidURL
        }
        let cookieJar = MediaCookieJar()

        if isDirectMediaResource(rootURL) {
            return videoSource(
                url: rootURL,
                plugin: plugin,
                referer: plugin.referer ?? plugin.baseURL,
                cookieJar: cookieJar
            )
        }

        var pending: [NativePageRequest] = [
            NativePageRequest(url: rootURL, depth: 0, referer: plugin.referer ?? plugin.baseURL)
        ]
        var seenPages = Set<String>()
        var candidates: [NativeVideoCandidate] = []
        var seenCandidates = Set<String>()

        while !pending.isEmpty {
            let request = pending.removeFirst()
            let pageKey = request.url.absoluteString
            guard request.depth <= maxDepth, !seenPages.contains(pageKey) else { continue }
            seenPages.insert(pageKey)

            if isDirectMediaResource(request.url) {
                addCandidate(
                    NativeVideoCandidate(url: request.url, referer: request.referer, priority: 4),
                    to: &candidates,
                    seen: &seenCandidates
                )
                continue
            }

            do {
                let fetchedPage = try await fetchPage(url: request.url, plugin: plugin, referer: request.referer, cookieJar: cookieJar)
                let html = fetchedPage.html
                collectMediaCandidates(
                    from: html,
                    baseURL: fetchedPage.url,
                    referer: fetchedPage.url.absoluteString,
                    plugin: plugin,
                    priority: request.depth == 0 ? 3 : 2,
                    candidates: &candidates,
                    seenCandidates: &seenCandidates
                )

                for candidate in await baimaoVideoCandidates(
                    from: html,
                    pageURL: fetchedPage.url,
                    plugin: plugin,
                    cookieJar: cookieJar
                ) {
                    addCandidate(candidate, to: &candidates, seen: &seenCandidates)
                }

                for candidate in await gugu3VideoCandidates(
                    from: html,
                    pageURL: fetchedPage.url,
                    plugin: plugin,
                    cookieJar: cookieJar
                ) {
                    addCandidate(candidate, to: &candidates, seen: &seenCandidates)
                }

                let nextPages = collectPlayerPages(
                    from: html,
                    baseURL: fetchedPage.url,
                    plugin: plugin
                ) + collectScriptPages(from: html, baseURL: fetchedPage.url)
                for nextPage in nextPages where request.depth < maxDepth {
                    if isDirectMediaResource(nextPage) {
                        addCandidate(
                            NativeVideoCandidate(url: nextPage, referer: fetchedPage.url.absoluteString, priority: 4),
                            to: &candidates,
                            seen: &seenCandidates
                        )
                    } else {
                        pending.append(
                            NativePageRequest(
                                url: nextPage,
                                depth: request.depth + 1,
                                referer: fetchedPage.url.absoluteString
                            )
                        )
                    }
                }
            } catch {
                print("NativeVideoResolver: page fetch failed \(request.url): \(error)")
            }

            if let best = await firstPlayableCandidate(from: candidates, plugin: plugin, cookieJar: cookieJar) {
                return videoSource(url: best.url, plugin: plugin, referer: best.referer, cookieJar: cookieJar)
            }
        }

        if let best = await firstPlayableCandidate(from: candidates, plugin: plugin, cookieJar: cookieJar) {
            return videoSource(url: best.url, plugin: plugin, referer: best.referer, cookieJar: cookieJar)
        }

        throw VideoSourceError.videoSourceNotFound
    }

    private func fetchPage(url: URL, plugin: PluginRule, referer: String?, cookieJar: MediaCookieJar) async throws -> NativeFetchedPage {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        for (key, value) in requestHeaders(plugin: plugin, referer: referer, requestURL: url, cookieJar: cookieJar) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let responseURL = httpResponse.url ?? url
        cookieJar.storeCookies(from: httpResponse, for: responseURL)
        if let signal = WebChallengeDetector.detect(data: data, response: httpResponse) {
            throw videoSourceError(for: signal)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw APIError.decodingError
        }
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VideoSourceError.emptyHTML
        }
        return NativeFetchedPage(html: html, url: responseURL)
    }

    private func baimaoVideoCandidates(
        from html: String,
        pageURL: URL,
        plugin: PluginRule,
        cookieJar: MediaCookieJar
    ) async -> [NativeVideoCandidate] {
        guard isBaimaoPage(pageURL, plugin: plugin, html: html),
              let scriptURL = baimaoPlayerScriptURL(from: html, baseURL: pageURL) else {
            return []
        }

        do {
            let serverTime = (try? await fetchBaimaoServerTime(pageURL: pageURL, plugin: plugin, cookieJar: cookieJar))
                ?? "\(Int(Date().timeIntervalSince1970))"
            let scriptPage = try await fetchPage(url: scriptURL, plugin: plugin, referer: pageURL.absoluteString, cookieJar: cookieJar)
            guard let playRequest = baimaoPlaybackRequest(
                from: scriptPage.html,
                pageURL: pageURL,
                serverTime: serverTime,
                cookieHeader: cookieJar.cookieHeader(for: pageURL) ?? ""
            ),
                  let endpoint = playRequest.endpoint,
                  let endpointURL = URL(string: endpoint, relativeTo: pageURL)?.absoluteURL else {
                return []
            }

            let playInfo = try await fetchBaimaoPlayInfo(
                endpointURL: endpointURL,
                pageURL: pageURL,
                plugin: plugin,
                cookieHeader: playRequest.cookies ?? "",
                cookieJar: cookieJar
            )
            let values = baimaoPlayInfoValues(from: playInfo)
            var candidates: [NativeVideoCandidate] = []
            var seen = Set<String>()
            for value in values {
                guard let url = mediaURL(from: value, baseURL: pageURL) else { continue }
                let key = url.absoluteString
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                candidates.append(NativeVideoCandidate(url: url, referer: pageURL.absoluteString, priority: 8))
            }
            return candidates
        } catch {
            print("NativeVideoResolver: baimao native resolution failed: \(error)")
            return []
        }
    }

    private func isBaimaoPage(_ pageURL: URL, plugin: PluginRule, html: String) -> Bool {
        let host = pageURL.host?.lowercased() ?? ""
        let pluginName = plugin.name.lowercased()
        return pluginName.contains("baimao")
            || host.contains("baimaodm.com")
            || host.contains("bmmdm.com")
            || html.contains("setPlayFrm")
    }

    private func baimaoPlayerScriptURL(from html: String, baseURL: URL) -> URL? {
        if let doc = try? HTMLDocument(string: html) {
            for element in doc.xpath("//script") {
                guard let src = element.attr("src"),
                      src.contains("pck.js"),
                      let url = URL(string: src, relativeTo: baseURL)?.absoluteURL else {
                    continue
                }
                return url
            }
        }

        if let value = matches(in: html, patterns: [#"<script[^>]+src=["']([^"']*pck\.js[^"']*)["']"#]).first {
            return URL(string: value, relativeTo: baseURL)?.absoluteURL
        }

        return URL(string: "/hdst/js/pck.js", relativeTo: baseURL)?.absoluteURL
    }

    private func fetchBaimaoServerTime(pageURL: URL, plugin: PluginRule, cookieJar: MediaCookieJar) async throws -> String {
        guard let timeURL = URL(string: "/time", relativeTo: pageURL)?.absoluteURL else {
            throw VideoSourceError.invalidURL
        }
        let page = try await fetchPage(url: timeURL, plugin: plugin, referer: pageURL.absoluteString, cookieJar: cookieJar)
        return page.html.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func baimaoPlaybackRequest(
        from script: String,
        pageURL: URL,
        serverTime: String,
        cookieHeader: String
    ) -> BaimaoPlaybackRequest? {
        guard let context = JSContext() else { return nil }
        context.exceptionHandler = { _, exception in
            if let exception {
                print("NativeVideoResolver baimao JS error: \(exception)")
            }
        }

        let setupScript = """
        var __capturedGetURL = null;
        var __cookies = {};
        function __setCookiePair(pair) {
          var index = pair.indexOf('=');
          if (index <= 0) return;
          __cookies[pair.slice(0, index).trim()] = pair.slice(index + 1).trim();
        }
        function __loadCookieHeader(header) {
          String(header || '').split(';').forEach(function(part) {
            __setCookiePair(part.trim());
          });
        }
        function __cookieString() {
          return Object.keys(__cookies).map(function(name) {
            return name + '=' + __cookies[name];
          }).join('; ');
        }
        __loadCookieHeader(\(jsStringLiteral(cookieHeader)));
        var window = { location: { href: \(jsStringLiteral(pageURL.absoluteString)) } };
        var location = window.location;
        var navigator = { platform: 'Win32', maxTouchPoints: 0 };
        var document = {
          getElementById: function() { return { src: '' }; }
        };
        Object.defineProperty(document, 'cookie', {
          get: function() { return __cookieString(); },
          set: function(value) { __setCookiePair(String(value).split(';')[0]); }
        });
        var XMLHttpRequest = function() {
          this.open = function(method, url, async) { this.url = url; };
          this.send = function() {
            this.readyState = 4;
            this.status = 200;
            this.responseText = \(jsStringLiteral(serverTime));
            if (typeof this.onreadystatechange === 'function') {
              this.onreadystatechange();
            }
          };
        };
        var setInterval = function() { return 0; };
        var setTimeout = function(callback) {
          if (typeof callback === 'function') { callback(); }
          return 0;
        };
        if (typeof escape === 'undefined') {
          var escape = encodeURIComponent;
        }
        var $ = function() {
          return {
            html: function() {},
            removeAttr: function() {}
          };
        };
        $.get = function(url) {
          __capturedGetURL = url;
        };
        """
        context.evaluateScript(setupScript)
        context.evaluateScript(script)
        context.evaluateScript("if (typeof setPlayFrm === 'function') { setPlayFrm('hm_playfram'); }")
        guard let json = context
            .evaluateScript("JSON.stringify({ endpoint: __capturedGetURL, cookies: __cookieString() })")?
            .toString(),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(BaimaoPlaybackRequest.self, from: data)
    }

    private func fetchBaimaoPlayInfo(
        endpointURL: URL,
        pageURL: URL,
        plugin: PluginRule,
        cookieHeader: String,
        cookieJar: MediaCookieJar
    ) async throws -> String {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        var headers = playbackHeaders(plugin: plugin, referer: pageURL.absoluteString, requestURL: endpointURL, cookieJar: cookieJar)
        headers["Accept"] = "*/*"
        headers["X-Requested-With"] = "XMLHttpRequest"
        if !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }
        for (name, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        cookieJar.storeCookies(from: httpResponse, for: httpResponse.url ?? endpointURL)
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func baimaoPlayInfoValues(from responseText: String) -> [String] {
        let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("ipchk:") else {
            return []
        }

        let jsonText = trimmed.contains("{") ? trimmed : (decodeBaimaoHexPlayInfo(trimmed) ?? "")
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let playerPrefix = firstStringValue(in: object, keys: ["purl", "player", "parse"])
        let videoURL = firstStringValue(in: object, keys: ["vurl", "url", "file", "src", "playurl"])
        var values: [String] = []
        if let videoURL, !videoURL.isEmpty {
            values.append(videoURL)
            if let playerPrefix, !playerPrefix.isEmpty {
                values.append(playerPrefix + videoURL)
            }
        }
        return values
    }

    private func gugu3VideoCandidates(
        from html: String,
        pageURL: URL,
        plugin: PluginRule,
        cookieJar: MediaCookieJar
    ) async -> [NativeVideoCandidate] {
        guard isGugu3Page(pageURL, plugin: plugin, html: html) else {
            return []
        }

        var candidates: [NativeVideoCandidate] = []
        var seen = Set<String>()
        for config in playerConfigs(from: html) {
            let from = config.from?.lowercased() ?? ""
            for token in decodedPlayerValues(config.url, encrypt: config.encrypt) {
                guard from == "vwnet" || token.lowercased().hasPrefix("vwnet-"),
                      let playerURL = gugu3PlayerURL(token: token, pageURL: pageURL, html: html) else {
                    continue
                }

                do {
                    let playerPage = try await fetchPage(
                        url: playerURL,
                        plugin: plugin,
                        referer: pageURL.absoluteString,
                        cookieJar: cookieJar
                    )
                    guard let request = gugu3MizhiRequest(from: playerPage.html, fallbackToken: token) else {
                        continue
                    }
                    let responseText = try await fetchGugu3MizhiPlayInfo(
                        request: request,
                        playerURL: playerPage.url,
                        plugin: plugin,
                        cookieJar: cookieJar
                    )
                    for value in gugu3MizhiPlayInfoValues(from: responseText) {
                        guard let url = mediaURL(from: value, baseURL: playerPage.url),
                              !seen.contains(url.absoluteString) else {
                            continue
                        }
                        seen.insert(url.absoluteString)
                        candidates.append(
                            NativeVideoCandidate(
                                url: url,
                                referer: playerPage.url.absoluteString,
                                priority: 9
                            )
                        )
                    }
                } catch {
                    print("NativeVideoResolver: gugu3 vwnet resolution failed: \(error)")
                }
            }
        }
        return candidates
    }

    private func isGugu3Page(_ pageURL: URL, plugin: PluginRule, html: String) -> Bool {
        let host = pageURL.host?.lowercased() ?? ""
        let pluginName = plugin.name.lowercased()
        return pluginName.contains("gugu3")
            || host.contains("gugu3.com")
            || html.contains(#""from":"vwnet""#)
            || html.contains("'from':'vwnet'")
    }

    private func gugu3PlayerURL(token: String, pageURL: URL, html: String) -> URL? {
        guard var components = URLComponents(string: "https://player.gugu3.com/") else {
            return nil
        }
        var queryItems = [
            URLQueryItem(name: "url", value: token)
        ]
        let next = firstStringField(named: ["link_next"], in: html)
        if let next, !next.isEmpty {
            let host = pageURL.host ?? "www.gugu3.com"
            queryItems.append(URLQueryItem(name: "next", value: "//\(host)\(next)"))
        }
        components.queryItems = queryItems
        return components.url
    }

    private func gugu3MizhiRequest(from html: String, fallbackToken: String) -> Gugu3MizhiRequest? {
        let block = gugu3ConfigBlock(from: html) ?? html
        let token = firstStringField(named: ["url"], in: block) ?? fallbackToken
        guard !token.isEmpty else {
            return nil
        }
        return Gugu3MizhiRequest(
            url: token,
            time: firstStringField(named: ["time"], in: block) ?? "",
            key: firstStringField(named: ["key"], in: block) ?? "",
            vkey: firstStringField(named: ["vkey"], in: block) ?? ""
        )
    }

    private func gugu3ConfigBlock(from html: String) -> String? {
        let pattern = #"(?is)var\s+config\s*=\s*\{(.*?)\};"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let nsText = html as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
    }

    private func fetchGugu3MizhiPlayInfo(
        request playRequest: Gugu3MizhiRequest,
        playerURL: URL,
        plugin: PluginRule,
        cookieJar: MediaCookieJar
    ) async throws -> String {
        guard let endpointURL = URL(string: "https://player.gugu3.com/admin/mizhi_json.php") else {
            throw VideoSourceError.invalidURL
        }
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.httpBody = formURLEncodedBody([
            ("url", playRequest.url),
            ("time", playRequest.time),
            ("key", playRequest.key),
            ("vkey", playRequest.vkey)
        ])

        var headers = playbackHeaders(
            plugin: plugin,
            referer: playerURL.absoluteString,
            requestURL: endpointURL,
            cookieJar: cookieJar
        )
        headers["Accept"] = "application/json,text/javascript,*/*;q=0.8"
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
        headers["Origin"] = "https://player.gugu3.com"
        headers["X-Requested-With"] = "XMLHttpRequest"
        for (name, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        cookieJar.storeCookies(from: httpResponse, for: httpResponse.url ?? endpointURL)
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func gugu3MizhiPlayInfoValues(from responseText: String) -> [String] {
        guard let data = responseText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let keys = ["url", "json_url", "playurl", "video_url", "file", "src"]
        var values: [String] = []
        var seen = Set<String>()
        for key in keys {
            guard let value = object[key] as? String,
                  !value.isEmpty,
                  !seen.contains(value) else {
                continue
            }
            seen.insert(value)
            values.append(value)
        }
        return values
    }

    private func decodeBaimaoHexPlayInfo(_ value: String) -> String? {
        let characters = Array(value)
        guard !characters.isEmpty, characters.count % 2 == 0 else {
            return nil
        }

        let totalBytes = characters.count / 2
        var bytes: [UInt8] = []
        for index in stride(from: 0, to: characters.count, by: 2) {
            let hex = String(characters[index]) + String(characters[index + 1])
            guard let rawByte = Int(hex, radix: 16) else {
                return nil
            }
            let position = index / 2
            let decoded = (rawByte + 0x100000 - 0x943 - (totalBytes - 1 - position)) % 0x100
            bytes.insert(UInt8(decoded), at: 0)
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private func firstStringValue(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                return value
            }
        }
        return nil
    }

    private func collectMediaCandidates(
        from text: String,
        baseURL: URL,
        referer: String,
        plugin: PluginRule,
        priority: Int,
        candidates: inout [NativeVideoCandidate],
        seenCandidates: inout Set<String>
    ) {
        let patterns = plugin.mediaPatterns?.filter { !$0.isEmpty } ?? defaultMediaPatterns
        for value in matches(in: text, patterns: patterns) {
            guard let url = mediaURL(from: value, baseURL: baseURL) else { continue }
            addCandidate(
                NativeVideoCandidate(url: url, referer: referer, priority: priority),
                to: &candidates,
                seen: &seenCandidates
            )
        }

        for decoded in decodedJavaScriptStrings(from: text) {
            for value in matches(in: decoded, patterns: defaultMediaPatterns) {
                guard let url = mediaURL(from: value, baseURL: baseURL) else { continue }
                addCandidate(
                    NativeVideoCandidate(url: url, referer: referer, priority: priority + 1),
                    to: &candidates,
                    seen: &seenCandidates
                )
            }
        }

        for config in playerConfigs(from: text) {
            for value in decodedPlayerValues(config.url, encrypt: config.encrypt) {
                guard let url = mediaURL(from: value, baseURL: baseURL) else { continue }
                addCandidate(
                    NativeVideoCandidate(url: url, referer: referer, priority: priority + 3),
                    to: &candidates,
                    seen: &seenCandidates
                )
            }
        }

        for value in encryptedPlayerURLs(from: text) {
            guard let url = mediaURL(from: value, baseURL: baseURL) else { continue }
            addCandidate(
                NativeVideoCandidate(url: url, referer: referer, priority: priority + 4),
                to: &candidates,
                seen: &seenCandidates
            )
        }

        guard let doc = try? HTMLDocument(string: text) else { return }

        for element in doc.xpath("//video") {
            for attribute in ["src", "data-src", "data-url", "data-play", "data-original"] {
                guard let value = element.attr(attribute),
                      let url = mediaURL(from: value, baseURL: baseURL) else {
                    continue
                }
                addCandidate(
                    NativeVideoCandidate(url: url, referer: referer, priority: priority + 2),
                    to: &candidates,
                    seen: &seenCandidates
                )
            }
        }

        for element in doc.xpath("//source") {
            for attribute in ["src", "data-src", "data-url", "data-play", "data-original"] {
                guard let value = element.attr(attribute),
                      let url = mediaURL(from: value, baseURL: baseURL) else {
                    continue
                }
                addCandidate(
                    NativeVideoCandidate(url: url, referer: referer, priority: priority + 2),
                    to: &candidates,
                    seen: &seenCandidates
                )
            }
        }

        for script in doc.xpath("//script") {
            collectMediaCandidates(
                from: script.stringValue,
                baseURL: baseURL,
                referer: referer,
                plugin: plugin,
                priority: priority,
                candidates: &candidates,
                seenCandidates: &seenCandidates
            )
        }
    }

    private func collectPlayerPages(from text: String, baseURL: URL, plugin: PluginRule) -> [URL] {
        var pages: [URL] = []
        var seen = Set<String>()

        func addPage(_ value: String) {
            let normalized = normalizeCandidateValue(value)
            guard let url = URL(string: normalized, relativeTo: baseURL)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  !seen.contains(url.absoluteString),
                  !shouldIgnoreURL(url.absoluteString.lowercased()) else {
                return
            }
            seen.insert(url.absoluteString)
            pages.append(url)
        }

        if let doc = try? HTMLDocument(string: text) {
            for element in doc.xpath("//iframe") {
                for attribute in ["src", "data-src", "data-url", "data-play"] {
                    if let value = element.attr(attribute), !value.isEmpty {
                        addPage(value)
                    }
                }
            }

            for element in doc.xpath("//embed") {
                for attribute in ["src", "data-src", "data-url", "data-play"] {
                    if let value = element.attr(attribute), !value.isEmpty {
                        addPage(value)
                    }
                }
            }
        }

        let patterns = plugin.iframePatterns?.filter { !$0.isEmpty } ?? defaultPlayerPagePatterns
        for value in matches(in: text, patterns: patterns) {
            addPage(value)
        }

        for config in playerConfigs(from: text) {
            for value in decodedPlayerValues(config.url, encrypt: config.encrypt) {
                if config.from?.lowercased() == "vwnet" || value.lowercased().hasPrefix("vwnet-") {
                    continue
                }
                if mediaURL(from: value, baseURL: baseURL) != nil {
                    continue
                }
                if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("/") || value.contains("player") || value.contains("parse") {
                    addPage(value)
                }
                let encoded = percentEncodedQueryValue(value)
                addPage("/player/?url=\(encoded)")
                addPage("/parse/?url=\(encoded)")
            }
        }

        return pages
    }

    private func collectScriptPages(from text: String, baseURL: URL) -> [URL] {
        var pages: [URL] = []
        var seen = Set<String>()

        func addScript(_ value: String) {
            let normalized = normalizeCandidateValue(value)
            guard let url = URL(string: normalized, relativeTo: baseURL)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  !seen.contains(url.absoluteString),
                  shouldFollowScriptURL(url, from: baseURL) else {
                return
            }
            seen.insert(url.absoluteString)
            pages.append(url)
        }

        if let doc = try? HTMLDocument(string: text) {
            for element in doc.xpath("//script") {
                if let value = element.attr("src"), !value.isEmpty {
                    addScript(value)
                }
            }
        }

        let pattern = #"<script[^>]+src=["']([^"']+)["']"#
        for value in matches(in: text, patterns: [pattern]) {
            addScript(value)
        }

        return pages
    }

    private func mediaURL(from rawValue: String, baseURL: URL) -> URL? {
        for value in decodedCandidateValues(rawValue) {
            guard let resolved = URL(string: value, relativeTo: baseURL)?.absoluteURL else {
                continue
            }

            let unwrapped = unwrapNestedMediaURL(resolved, baseURL: baseURL)
            guard isDirectMediaResource(unwrapped),
                  !shouldIgnoreURL(unwrapped.absoluteString.lowercased()) else {
                continue
            }
            return unwrapped
        }
        return nil
    }

    private func unwrapNestedMediaURL(_ url: URL, baseURL: URL) -> URL {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        let preferredKeys = ["url", "playurl", "play_url", "file", "src", "source", "video", "path"]
        let queryItems = components.queryItems ?? []
        let nestedValues = preferredKeys.flatMap { key in
            queryItems.filter { $0.name.lowercased() == key }.compactMap(\.value)
        } + queryItems.compactMap { item in
            guard let value = item.value,
                  looksLikeNestedMediaURL(value) else {
                return nil
            }
            return value
        }

        for value in nestedValues {
            let normalized = normalizeCandidateValue(value)
            if let nestedURL = URL(string: normalized, relativeTo: url)?.absoluteURL,
               nestedURL != url,
               isDirectMediaResource(nestedURL) {
                return nestedURL
            }
        }

        return url
    }

    private func matches(in text: String, patterns: [String]) -> [String] {
        var values: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            for match in regex.matches(in: text, range: range) {
                var captured: String?
                if match.numberOfRanges > 1 {
                    for index in 1..<match.numberOfRanges where match.range(at: index).location != NSNotFound {
                        captured = nsText.substring(with: match.range(at: index))
                        break
                    }
                }
                values.append(captured ?? nsText.substring(with: match.range))
            }
        }
        return values
    }

    private func decodedJavaScriptStrings(from source: String) -> [String] {
        var values: [String] = []

        let base64Pattern = #"atob\(\s*["']([^"']+)["']\s*\)"#
        for encoded in matches(in: source, patterns: [base64Pattern]) {
            if let data = Data(base64Encoded: encoded),
               let decoded = String(data: data, encoding: .utf8) {
                values.append(decoded)
            }
        }

        let encodedPattern = #"(?:decodeURIComponent|unescape)\(\s*["']([^"']+)["']\s*\)"#
        for encoded in matches(in: source, patterns: [encodedPattern]) {
            values.append(encoded.removingPercentEncoding ?? encoded)
        }

        guard let context = JSContext() else {
            return values
        }
        context.exceptionHandler = { _, exception in
            if let exception {
                print("NativeVideoResolver JS error: \(exception)")
            }
        }
        let encodedSource = (try? String(data: JSONEncoder().encode(source), encoding: .utf8)) ?? "\"\""
        let script = """
        (() => {
          const source = \(encodedSource);
          const hits = [];
          const literalConcat = String.raw`(?:"[^"]*"|'[^']*')\\\\s*(?:\\\\+\\\\s*(?:"[^"]*"|'[^']*')\\\\s*)+`;
          const evalStringLiteralExpression = (expr) => {
            try {
              const value = Function('"use strict"; return (' + expr + ');')();
              if (typeof value === 'string') hits.push(value);
            } catch (_) {}
          };
          source.replace(/['"]((?:https?:)?\\/\\/[^'"\\s<>]+)['"]/g, (_, value) => hits.push(value));
          source.replace(/['"]([^'"]+\\.(?:m3u8|mp4|m4v|mov)(?:[?#][^'"]*)?)['"]/gi, (_, value) => hits.push(value));
          source.replace(new RegExp('(?:var|let|const)\\\\s+[$A-Z_a-z][$\\\\w]*\\\\s*=\\\\s*(' + literalConcat + ')', 'g'), (_, expr) => evalStringLiteralExpression(expr));
          return JSON.stringify(hits);
        })()
        """
        if let json = context.evaluateScript(script)?.toString(),
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            values.append(contentsOf: decoded)
        }

        return values
    }

    private func playerConfigs(from text: String) -> [NativePlayerConfig] {
        var configs: [NativePlayerConfig] = []

        for block in playerConfigBlocks(from: text) {
            guard let url = firstStringField(named: ["url", "file", "src", "playurl", "play_url"], in: block),
                  !url.isEmpty else {
                continue
            }
            configs.append(
                NativePlayerConfig(
                    url: url,
                    from: firstStringField(named: ["from"], in: block),
                    encrypt: firstIntField(named: "encrypt", in: block)
                )
            )
        }

        return configs
    }

    private func playerConfigBlocks(from text: String) -> [String] {
        var blocks: [String] = []
        let markers = ["player_aaaa", "player_data", "MacPlayer"]

        let pattern = #"(?is)<script[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return markers.contains(where: { text.contains($0) }) ? [text] : []
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        for match in regex.matches(in: text, range: range) where match.numberOfRanges > 1 {
            let block = nsText.substring(with: match.range(at: 1))
            if markers.contains(where: { block.contains($0) }) {
                blocks.append(block)
            }
        }
        if blocks.isEmpty, markers.contains(where: { text.contains($0) }) {
            blocks.append(text)
        }
        return blocks
    }

    private func encryptedPlayerURLs(from text: String) -> [String] {
        guard let encryptedURL = firstStringField(named: ["encryptedUrl"], in: text),
              let sessionKey = firstStringField(named: ["sessionKey"], in: text),
              let decrypted = decryptAESCBCBase64(ciphertext: encryptedURL, key: sessionKey),
              !decrypted.isEmpty else {
            return []
        }
        return [decrypted]
    }

    private func decodedPlayerValues(_ value: String, encrypt: Int?) -> [String] {
        switch encrypt {
        case 1:
            return decodedCandidateValues(jsUnescape(value))
        case 2:
            let unescaped = jsUnescape(value)
            guard let decoded = base64DecodedString(unescaped) else {
                return decodedCandidateValues(unescaped)
            }
            return decodedCandidateValues(jsUnescape(decoded))
        default:
            return decodedCandidateValues(value)
        }
    }

    private func decodedCandidateValues(_ rawValue: String) -> [String] {
        var values: [String] = []
        var seen = Set<String>()

        func add(_ value: String?) {
            guard let value else { return }
            let normalized = normalizeCandidateValue(value)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return }
            seen.insert(normalized)
            values.append(normalized)
        }

        add(rawValue)
        add(jsUnescape(rawValue))
        add(rawValue.removingPercentEncoding)

        if let decoded = base64DecodedString(rawValue) {
            add(decoded)
            add(jsUnescape(decoded))
        }

        let reversed = String(rawValue.reversed())
        if looksLikeNestedMediaURL(reversed) || reversed.lowercased().contains("8u3m.") || reversed.lowercased().contains("4pm.") {
            add(reversed)
        }

        return values
    }

    private func firstStringField(named names: [String], in text: String) -> String? {
        for name in names {
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            let pattern = #"(?is)["']?\#(escapedName)["']?\s*[:=]\s*["']([^"']+)["']"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            if let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 {
                return nsText.substring(with: match.range(at: 1))
            }
        }
        return nil
    }

    private func firstIntField(named name: String, in text: String) -> Int? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?is)["']?\#(escapedName)["']?\s*[:=]\s*["']?(\d+)["']?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return nil
        }
        return Int(nsText.substring(with: match.range(at: 1)))
    }

    private func base64DecodedString(_ value: String) -> String? {
        var normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        while normalized.count % 4 != 0 {
            normalized.append("=")
        }

        guard let data = Data(base64Encoded: normalized),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return decoded
    }

    private func decryptAESCBCBase64(ciphertext: String, key: String) -> String? {
        guard let rawData = Data(base64Encoded: ciphertext),
              rawData.count > kCCBlockSizeAES128,
              let keyData = key.data(using: .utf8),
              [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256].contains(keyData.count) else {
            return nil
        }

        let ivData = rawData.prefix(kCCBlockSizeAES128)
        let encryptedData = rawData.dropFirst(kCCBlockSizeAES128)
        var output = Data(count: encryptedData.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0

        let status = keyData.withUnsafeBytes { keyBytes in
            ivData.withUnsafeBytes { ivBytes in
                encryptedData.withUnsafeBytes { encryptedBytes in
                    output.withUnsafeMutableBytes { outputBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            keyData.count,
                            ivBytes.baseAddress,
                            encryptedBytes.baseAddress,
                            encryptedData.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            return nil
        }

        output.removeSubrange(outputLength..<output.count)
        return String(data: output, encoding: .utf8)
    }

    private func addCandidate(
        _ candidate: NativeVideoCandidate,
        to candidates: inout [NativeVideoCandidate],
        seen: inout Set<String>
    ) {
        let key = candidate.url.absoluteString
        guard !seen.contains(key) else { return }
        seen.insert(key)
        candidates.append(candidate)
    }

    private func bestCandidate(from candidates: [NativeVideoCandidate]) -> NativeVideoCandidate? {
        sortedCandidates(candidates).first
    }

    private func sortedCandidates(_ candidates: [NativeVideoCandidate]) -> [NativeVideoCandidate] {
        candidates.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            if isPlaylistURL(lhs.url) != isPlaylistURL(rhs.url) {
                return isPlaylistURL(lhs.url)
            }
            return lhs.url.absoluteString < rhs.url.absoluteString
        }
    }

    private func firstPlayableCandidate(from candidates: [NativeVideoCandidate], plugin: PluginRule, cookieJar: MediaCookieJar) async -> NativeVideoCandidate? {
        for candidate in sortedCandidates(candidates) {
            if await isPlayableCandidate(candidate, plugin: plugin, cookieJar: cookieJar) {
                return candidate
            }
        }
        return nil
    }

    private func isPlayableCandidate(_ candidate: NativeVideoCandidate, plugin: PluginRule, cookieJar: MediaCookieJar) async -> Bool {
        if isPlaylistURL(candidate.url) {
            return await validatePlaylistCandidate(candidate, plugin: plugin, cookieJar: cookieJar)
        }

        return await validateDirectMediaCandidate(candidate, plugin: plugin, cookieJar: cookieJar)
    }

    private func validatePlaylistCandidate(_ candidate: NativeVideoCandidate, plugin: PluginRule, cookieJar: MediaCookieJar) async -> Bool {
        var request = URLRequest(url: candidate.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        request.setValue("application/vnd.apple.mpegurl,application/x-mpegURL,*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        for (name, value) in playbackHeaders(plugin: plugin, referer: candidate.referer, requestURL: candidate.url, cookieJar: cookieJar) where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (data, response) = try await validationSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("NativeVideoResolver: candidate validation failed, invalid response: \(candidate.url)")
                return false
            }
            cookieJar.storeCookies(from: httpResponse, for: candidate.url)
            if let signal = WebChallengeDetector.detect(data: data, response: httpResponse) {
                print("NativeVideoResolver: candidate validation failed, \(signal.displayName): \(candidate.url)")
                return false
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                print("NativeVideoResolver: candidate validation failed, HTTP \(httpResponse.statusCode): \(candidate.url)")
                return false
            }
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            let inspection = HLSPlaylistInspector.inspect(text, url: candidate.url)
            if inspection.isLikelyPlayable {
                return true
            }
            print("NativeVideoResolver: candidate validation failed, \(inspection.reason ?? "unplayable playlist"): \(candidate.url)")
            return false
        } catch {
            if shouldRetryByUpgradingToHTTPS(error: error, url: candidate.url),
               let upgradedURL = httpsURL(for: candidate.url) {
                let upgradedCandidate = NativeVideoCandidate(
                    url: upgradedURL,
                    referer: candidate.referer,
                    priority: candidate.priority
                )
                return await validatePlaylistCandidate(upgradedCandidate, plugin: plugin, cookieJar: cookieJar)
            }
            print("NativeVideoResolver: candidate validation failed: \(candidate.url), error: \(error)")
            return false
        }
    }

    private func validateDirectMediaCandidate(_ candidate: NativeVideoCandidate, plugin: PluginRule, cookieJar: MediaCookieJar) async -> Bool {
        var request = URLRequest(url: candidate.url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        for (name, value) in playbackHeaders(plugin: plugin, referer: candidate.referer, requestURL: candidate.url, cookieJar: cookieJar) where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (_, response) = try await validationSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("NativeVideoResolver: direct candidate validation failed, invalid response: \(candidate.url)")
                return false
            }
            cookieJar.storeCookies(from: httpResponse, for: candidate.url)
            if (200...399).contains(httpResponse.statusCode), !isHTMLLikeContentType(httpResponse) {
                return true
            }
            if [403, 405, 501].contains(httpResponse.statusCode) {
                return await validateDirectMediaCandidateWithRange(candidate, plugin: plugin, cookieJar: cookieJar)
            }
            print("NativeVideoResolver: direct candidate validation failed, HTTP \(httpResponse.statusCode): \(candidate.url)")
            return false
        } catch {
            if shouldRetryByUpgradingToHTTPS(error: error, url: candidate.url),
               let upgradedURL = httpsURL(for: candidate.url) {
                let upgradedCandidate = NativeVideoCandidate(
                    url: upgradedURL,
                    referer: candidate.referer,
                    priority: candidate.priority
                )
                return await validateDirectMediaCandidate(upgradedCandidate, plugin: plugin, cookieJar: cookieJar)
            }
            print("NativeVideoResolver: direct candidate validation failed: \(candidate.url), error: \(error)")
            return false
        }
    }

    private func validateDirectMediaCandidateWithRange(_ candidate: NativeVideoCandidate, plugin: PluginRule, cookieJar: MediaCookieJar) async -> Bool {
        var request = URLRequest(url: candidate.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        for (name, value) in playbackHeaders(plugin: plugin, referer: candidate.referer, requestURL: candidate.url, cookieJar: cookieJar) where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (_, response) = try await validationSession.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("NativeVideoResolver: direct range validation failed, invalid response: \(candidate.url)")
                return false
            }
            cookieJar.storeCookies(from: httpResponse, for: candidate.url)
            if (200...399).contains(httpResponse.statusCode), !isHTMLLikeContentType(httpResponse) {
                return true
            }
            print("NativeVideoResolver: direct range validation failed, HTTP \(httpResponse.statusCode): \(candidate.url)")
            return false
        } catch {
            if shouldRetryByUpgradingToHTTPS(error: error, url: candidate.url),
               let upgradedURL = httpsURL(for: candidate.url) {
                let upgradedCandidate = NativeVideoCandidate(
                    url: upgradedURL,
                    referer: candidate.referer,
                    priority: candidate.priority
                )
                return await validateDirectMediaCandidateWithRange(upgradedCandidate, plugin: plugin, cookieJar: cookieJar)
            }
            print("NativeVideoResolver: direct range validation failed: \(candidate.url), error: \(error)")
            return false
        }
    }

    private func httpsURL(for url: URL) -> URL? {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        return components.url
    }

    private func shouldRetryByUpgradingToHTTPS(error: Error, url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http" else { return false }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
            && nsError.code == NSURLErrorAppTransportSecurityRequiresSecureConnection
    }

    private func isHTMLLikeContentType(_ response: HTTPURLResponse) -> Bool {
        let contentType = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        return contentType.contains("text/html") || contentType.contains("application/xhtml")
    }

    private func videoSource(url: URL, plugin: PluginRule, referer: String?, cookieJar: MediaCookieJar) -> VideoSource {
        VideoSource(
            url: url,
            quality: "默认",
            pluginName: plugin.name,
            referer: referer,
            headers: playbackHeaders(plugin: plugin, referer: referer, requestURL: url, cookieJar: cookieJar)
        )
    }

    private func requestHeaders(plugin: PluginRule, referer: String?, requestURL: URL, cookieJar: MediaCookieJar) -> [String: String] {
        var headers = playbackHeaders(plugin: plugin, referer: referer, requestURL: requestURL, cookieJar: cookieJar)
        headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        headers["Accept-Language"] = "zh-CN,zh;q=0.9,en;q=0.8"
        headers["Connection"] = "keep-alive"
        headers["Cache-Control"] = "no-cache"
        headers["DNT"] = "1"
        headers["Pragma"] = "no-cache"
        headers["Sec-Fetch-Dest"] = "document"
        headers["Sec-Fetch-Mode"] = "navigate"
        headers["Sec-Fetch-Site"] = secFetchSite(requestURL: requestURL, referer: referer, plugin: plugin)
        headers["Sec-Fetch-User"] = "?1"
        headers["Upgrade-Insecure-Requests"] = "1"
        return headers
    }

    private func playbackHeaders(plugin: PluginRule, referer: String?, requestURL: URL, cookieJar: MediaCookieJar) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": plugin.userAgent.isEmpty ? defaultUserAgent : plugin.userAgent,
            "Accept": "*/*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
        ]
        if let playbackHeaders = plugin.playbackHeaders {
            for (name, value) in playbackHeaders where !value.isEmpty {
                headers[name] = value
            }
        }
        let effectiveReferer = referer?.isEmpty == false ? referer : (plugin.referer?.isEmpty == false ? plugin.referer : plugin.baseURL)
        if let effectiveReferer, !effectiveReferer.isEmpty {
            headers["Referer"] = effectiveReferer
            if headers["Origin"] == nil, let origin = originString(from: effectiveReferer) {
                headers["Origin"] = origin
            }
        }
        return cookieJar.headersByAddingCookies(headers, for: requestURL)
    }

    private func normalizedURLString(_ value: String, baseURL: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }
        var base = baseURL
        if base.hasSuffix("/") {
            base.removeLast()
        }
        if trimmed.hasPrefix("/") {
            return base + trimmed
        }
        return base + "/" + trimmed
    }

    private func normalizeCandidateValue(_ value: String) -> String {
        var result = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
        result = result.removingPercentEncoding ?? result
        if result.hasPrefix("//") {
            result = "https:" + result
        }
        return result
    }

    private func jsUnescape(_ value: String) -> String {
        var output = ""
        var index = value.startIndex

        while index < value.endIndex {
            if value[index] == "%",
               value.distance(from: index, to: value.endIndex) >= 6 {
                let markerIndex = value.index(after: index)
                if value[markerIndex] == "u" || value[markerIndex] == "U" {
                    let hexStart = value.index(after: markerIndex)
                    let hexEnd = value.index(hexStart, offsetBy: 4)
                    let hex = String(value[hexStart..<hexEnd])
                    if let scalarValue = UInt32(hex, radix: 16),
                       let scalar = UnicodeScalar(scalarValue) {
                        output.unicodeScalars.append(scalar)
                        index = hexEnd
                        continue
                    }
                }
            }

            output.append(value[index])
            index = value.index(after: index)
        }

        return output.removingPercentEncoding ?? output
    }

    private func percentEncodedQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func formURLEncodedBody(_ items: [(String, String)]) -> Data {
        let body = items
            .map { key, value in
                "\(percentEncodedQueryValue(key))=\(percentEncodedQueryValue(value))"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private func jsStringLiteral(_ value: String) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "\"\""
    }

    private func isDirectMediaResource(_ url: URL) -> Bool {
        isPlaylistURL(url) || isDirectFileVideoURL(url) || isProbableExtensionlessVideoURL(url)
    }

    private func isPlaylistURL(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        return value.contains(".m3u8")
            || path.hasSuffix("/manifest")
            || path.hasSuffix("/playlist")
    }

    private func isDirectFileVideoURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix(".mp4") || path.hasSuffix(".m4v") || path.hasSuffix(".mov")
    }

    private func isProbableExtensionlessVideoURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let value = url.absoluteString.lowercased()
        guard !shouldIgnoreURL(value) else { return false }

        let hostMarkers = ["toutiao", "byte", "ixigua", "bfvvs", "ffzy", "fengbao", "baofeng", "ppqrrs", "mgtv", "bilivideo", "miguvideo", "alicdn", "akamaized", "bunnycdn"]
        return hostMarkers.contains { host.contains($0) }
    }

    private func isLikelyPlayerPage(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        if shouldIgnoreURL(value) { return false }
        if isDirectMediaResource(url) { return true }
        let markers = ["player", "play", "embed", "iframe", "video", "watch", "m3u8", "vip", "parse", "jx"]
        return markers.contains { value.contains($0) }
    }

    private func looksLikeNestedMediaURL(_ value: String) -> Bool {
        let normalized = normalizeCandidateValue(value).lowercased()
        let hasNetworkScheme = normalized.hasPrefix("http://") || normalized.hasPrefix("https://") || normalized.hasPrefix("//")
        return hasNetworkScheme && [".m3u8", ".mp4", ".m4v", ".mov"].contains { normalized.contains($0) }
    }

    private func shouldIgnoreURL(_ value: String) -> Bool {
        let markers = [
            "googleads",
            "googlesyndication",
            "doubleclick",
            "adtrafficquality",
            "consumer.huawei.com",
            "tvc-video.mp4",
            "prestrain",
            "devtools-detector",
            ".jpg",
            ".jpeg",
            ".png",
            ".gif",
            ".webp",
            ".svg",
            ".css",
            ".js",
            ".woff",
            ".ttf",
            "hm.baidu.com"
        ]
        return markers.contains { value.contains($0) }
    }

    private func shouldFollowScriptURL(_ url: URL, from baseURL: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        if value.contains("hm.baidu.com")
            || value.contains("google")
            || value.contains("analytics")
            || value.contains("ads")
            || value.contains("share")
            || value.contains("jquery")
            || value.contains("bootstrap") {
            return false
        }

        let sameHost = url.host?.lowercased() == baseURL.host?.lowercased()
        let usefulMarkers = ["player", "play", "parse", "video", "m3u8", "iframe", "embed", "mac"]
        return sameHost || usefulMarkers.contains { value.contains($0) }
    }

    private func originString(from referer: String) -> String? {
        guard let url = URL(string: referer),
              let scheme = url.scheme,
              let host = url.host else {
            return nil
        }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private func secFetchSite(requestURL: URL, referer: String?, plugin: PluginRule) -> String {
        let refererHost = referer.flatMap { URL(string: $0)?.host?.lowercased() }
            ?? URL(string: plugin.baseURL)?.host?.lowercased()
        guard let requestHost = requestURL.host?.lowercased(),
              let refererHost else {
            return "same-origin"
        }

        if requestHost == refererHost {
            return "same-origin"
        }

        return rootDomain(for: requestHost) == rootDomain(for: refererHost) ? "same-site" : "cross-site"
    }

    private func rootDomain(for host: String) -> String {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return host }
        return parts.suffix(2).joined(separator: ".")
    }

    private func videoSourceError(for signal: WebChallengeSignal) -> VideoSourceError {
        switch signal.kind {
        case .challenge:
            return .challengePage(vendor: signal.vendor)
        case .captcha:
            return .captchaRequired(vendor: signal.vendor)
        }
    }

    private var defaultMediaPatterns: [String] {
        [
            #"((?:https?:)?//[^"'\s<>\\]+?\.(?:m3u8|mp4|m4v|mov)(?:\?[^"'\s<>\\]*)?)"#,
            #"["']([^"']+\.(?:m3u8|mp4|m4v|mov)(?:[?#][^"']*)?)["']"#,
            #"(?:url|src|file|playurl|play_url|videoUrl|video_url)\s*[:=]\s*["']([^"']+)["']"#
        ]
    }

    private var defaultPlayerPagePatterns: [String] {
        [
            #"<iframe[^>]+src=["']([^"']+)["']"#,
            #"<embed[^>]+src=["']([^"']+)["']"#,
            #"(?:player|iframe|embed|playurl|play_url)\s*[:=]\s*["']([^"']+)["']"#
        ]
    }
}

private struct NativeFetchedPage {
    let html: String
    let url: URL
}

private struct NativePageRequest {
    let url: URL
    let depth: Int
    let referer: String?
}

private struct NativeVideoCandidate {
    let url: URL
    let referer: String?
    let priority: Int
}

private struct NativePlayerConfig {
    let url: String
    let from: String?
    let encrypt: Int?
}

private struct Gugu3MizhiRequest {
    let url: String
    let time: String
    let key: String
    let vkey: String
}

private struct BaimaoPlaybackRequest: Decodable {
    let endpoint: String?
    let cookies: String?
}
