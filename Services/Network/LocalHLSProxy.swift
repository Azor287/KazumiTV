//
//  LocalHLSProxy.swift
//  KazumiTV
//
//  In-app loopback proxy for AVPlayer. It binds only to 127.0.0.1 on the
//  Apple TV and rewrites HLS playlists so headers can be applied to every
//  playlist, key, init map, and media segment request.
//

import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

final class LocalHLSProxy {
    static let shared = LocalHLSProxy()

    private let lock = NSLock()
    private let cookieJar = MediaCookieJar()
    private var resources: [String: LocalProxyResource] = [:]
    private var channel: Channel?
    private var group: MultiThreadedEventLoopGroup?
    private var port: Int?

    private init() {}

    func proxiedSource(for source: VideoSource) throws -> VideoSource {
        let playbackURL = directPlaybackURL(for: source.url)
        let playbackSource = sourceByReplacingURL(source, with: playbackURL)

        guard isPlaylistURL(playbackURL) else {
            if playbackURL != source.url {
                print("LocalHLSProxy: upgraded direct media URL to HTTPS: \(playbackURL.absoluteString)")
            }
            return playbackSource
        }

        guard shouldProxy(url: playbackURL) else {
            return playbackSource
        }

        try startIfNeeded()

        guard let port else {
            throw LocalHLSProxyError.notRunning
        }

        let token = register(
            url: playbackURL,
            headers: playbackHeaders(for: playbackSource),
            sourcePage: playbackSource.referer
        )
        let route = isPlaylistURL(playbackURL) ? "playlist" : "media"
        guard let localURL = URL(string: "http://127.0.0.1:\(port)/\(route)/\(token)") else {
            throw LocalHLSProxyError.invalidLocalURL
        }

        return VideoSource(
            url: localURL,
            quality: playbackSource.quality,
            pluginName: playbackSource.pluginName,
            referer: nil,
            headers: [:]
        )
    }

    fileprivate func route(
        head: HTTPRequestHead,
        body: ByteBuffer?
    ) async -> LocalProxyResponse {
        guard head.method == .GET || head.method == .HEAD else {
            return LocalProxyResponse(statusCode: 405, headers: ["Allow": "GET, HEAD"], body: Data())
        }

        guard let components = URLComponents(string: "http://127.0.0.1\(head.uri)") else {
            return LocalProxyResponse(statusCode: 400, bodyText: "Bad request")
        }

        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count == 2 else {
            return LocalProxyResponse(statusCode: 404, bodyText: "Not found")
        }

        let route = parts[0]
        let token = parts[1]
        guard let resource = resource(for: token) else {
            return LocalProxyResponse(statusCode: 404, bodyText: "Unknown media token")
        }

        do {
            switch route {
            case "playlist":
                return try await playlistResponse(for: resource, requestHead: head)
            case "media":
                return try await mediaResponse(for: resource, requestHead: head)
            default:
                return LocalProxyResponse(statusCode: 404, bodyText: "Not found")
            }
        } catch {
            print("LocalHLSProxy: request failed for \(resource.url): \(error)")
            return LocalProxyResponse(statusCode: 502, bodyText: error.localizedDescription)
        }
    }

    private func startIfNeeded() throws {
        lock.lock()
        if channel != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let serverChannel = try ServerBootstrap(group: eventLoopGroup)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { [weak self] channel in
                    guard let self else {
                        return channel.eventLoop.makeSucceededVoidFuture()
                    }
                    return channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                        channel.pipeline.addHandler(LocalHLSProxyHandler(proxy: self))
                    }
                }
                .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .bind(host: "127.0.0.1", port: 0)
                .wait()

            guard let boundPort = serverChannel.localAddress?.port else {
                throw LocalHLSProxyError.notRunning
            }

            lock.lock()
            channel = serverChannel
            group = eventLoopGroup
            port = boundPort
            lock.unlock()

            print("LocalHLSProxy: listening on 127.0.0.1:\(boundPort)")
        } catch {
            try? eventLoopGroup.syncShutdownGracefully()
            throw error
        }
    }

    private func register(
        url: URL,
        headers: [String: String],
        sourcePage: String?
    ) -> String {
        let token = UUID().uuidString
        let resource = LocalProxyResource(
            url: url,
            headers: cookieJar.headersByAddingCookies(headers, for: url),
            sourcePage: sourcePage
        )

        lock.lock()
        resources[token] = resource
        lock.unlock()

        return token
    }

    private func resource(for token: String) -> LocalProxyResource? {
        lock.lock()
        defer { lock.unlock() }
        return resources[token]
    }

    private func playlistResponse(
        for resource: LocalProxyResource,
        requestHead: HTTPRequestHead
    ) async throws -> LocalProxyResponse {
        let (data, response) = try await fetchRemote(
            resource: resource,
            requestHead: requestHead,
            accept: "application/vnd.apple.mpegurl,application/x-mpegURL,*/*",
            includeRange: false
        )

        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else {
            print("LocalHLSProxy: upstream did not return HLS playlist, status=\(response.statusCode), url=\(resource.url)")
            return LocalProxyResponse(statusCode: 502, bodyText: "远端没有返回 HLS 播放列表")
        }

        let rewritten = rewritePlaylist(text, playlistURL: response.url ?? resource.url, resource: resource)
        let body = requestHead.method == .HEAD ? Data() : Data(rewritten.utf8)
        return LocalProxyResponse(
            statusCode: 200,
            headers: [
                "Content-Type": "application/vnd.apple.mpegurl; charset=utf-8",
                "Content-Length": "\(body.count)",
                "Cache-Control": "no-cache",
                "Access-Control-Allow-Origin": "*"
            ],
            body: body
        )
    }

    private func mediaResponse(
        for resource: LocalProxyResource,
        requestHead: HTTPRequestHead
    ) async throws -> LocalProxyResponse {
        let (data, response) = try await fetchRemote(
            resource: resource,
            requestHead: requestHead,
            accept: "*/*",
            includeRange: true
        )
        var headers = filteredResponseHeaders(from: response, fallbackContentType: guessContentType(for: resource.url))
        headers["Accept-Ranges"] = headers["Accept-Ranges"] ?? "bytes"
        headers["Access-Control-Allow-Origin"] = "*"
        if headers["Content-Length"] == nil {
            headers["Content-Length"] = "\(data.count)"
        }

        return LocalProxyResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: requestHead.method == .HEAD ? Data() : data
        )
    }

    private func fetchRemote(
        resource: LocalProxyResource,
        requestHead: HTTPRequestHead,
        accept: String,
        includeRange: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: resource.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 45
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let headers = cookieJar.headersByAddingCookies(resource.headers, for: resource.url)
        for (name, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }

        if includeRange {
            for headerName in ["Range", "If-Range", "If-None-Match", "If-Modified-Since"] {
                if let value = requestHead.headers.first(name: headerName) {
                    request.setValue(value, forHTTPHeaderField: headerName)
                }
            }
        }

        let dataAndResponse: (Data, URLResponse)
        do {
            dataAndResponse = try await URLSession.shared.data(for: request)
        } catch {
            guard shouldRetryByUpgradingToHTTPS(error: error, url: resource.url),
                  let upgradedURL = httpsURL(for: resource.url) else {
                throw error
            }
            print("LocalHLSProxy: retrying insecure media over HTTPS: \(upgradedURL.absoluteString)")
            let upgradedResource = LocalProxyResource(
                url: upgradedURL,
                headers: resource.headers,
                sourcePage: resource.sourcePage
            )
            return try await fetchRemote(
                resource: upgradedResource,
                requestHead: requestHead,
                accept: accept,
                includeRange: includeRange
            )
        }
        let (data, response) = dataAndResponse
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalHLSProxyError.invalidResponse
        }
        cookieJar.storeCookies(from: httpResponse, for: resource.url)
        guard (200...399).contains(httpResponse.statusCode) else {
            print("LocalHLSProxy: upstream HTTP \(httpResponse.statusCode), url=\(resource.url)")
            throw LocalHLSProxyError.upstreamStatus(httpResponse.statusCode)
        }
        return (data, httpResponse)
    }

    private func rewritePlaylist(
        _ text: String,
        playlistURL: URL,
        resource: LocalProxyResource
    ) -> String {
        var output: [String] = []
        var nextLineIsVariantPlaylist = false

        for line in text.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped.isEmpty {
                output.append(line)
                continue
            }

            if stripped.hasPrefix("#") {
                output.append(rewriteURIAttributes(in: line, playlistURL: playlistURL, resource: resource))
                nextLineIsVariantPlaylist = stripped.hasPrefix("#EXT-X-STREAM-INF")
                continue
            }

            guard let absoluteURL = URL(string: stripped, relativeTo: playlistURL)?.absoluteURL else {
                output.append(line)
                nextLineIsVariantPlaylist = false
                continue
            }

            output.append(localURLString(
                for: absoluteURL,
                inheritedFrom: resource,
                isPlaylist: nextLineIsVariantPlaylist || isPlaylistURL(absoluteURL)
            ))
            nextLineIsVariantPlaylist = false
        }

        return output.joined(separator: "\n")
    }

    private func rewriteURIAttributes(
        in line: String,
        playlistURL: URL,
        resource: LocalProxyResource
    ) -> String {
        let pattern = #"URI="([^"]+)"|URI=([^,]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return line
        }

        let nsLine = line as NSString
        var rewritten = line
        for match in regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)).reversed() {
            let rawRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard rawRange.location != NSNotFound else { continue }

            let rawURI = nsLine.substring(with: rawRange)
            guard !rawURI.hasPrefix("data:"),
                  let absoluteURL = URL(string: rawURI, relativeTo: playlistURL)?.absoluteURL else {
                continue
            }

            let local = localURLString(
                for: absoluteURL,
                inheritedFrom: resource,
                isPlaylist: isPlaylistURL(absoluteURL)
            )
            let replacement = #"URI="\#(local)""#
            if let range = Range(match.range, in: rewritten) {
                rewritten.replaceSubrange(range, with: replacement)
            }
        }

        return rewritten
    }

    private func localURLString(
        for remoteURL: URL,
        inheritedFrom resource: LocalProxyResource,
        isPlaylist: Bool
    ) -> String {
        let token = register(
            url: remoteURL,
            headers: resource.headers,
            sourcePage: resource.sourcePage
        )
        let route = isPlaylist ? "playlist" : "media"
        let boundPort = port ?? 0
        return "http://127.0.0.1:\(boundPort)/\(route)/\(token)"
    }

    private func playbackHeaders(for source: VideoSource) -> [String: String] {
        var headers = source.headers
        if headers["User-Agent"] == nil {
            headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
        }
        if let referer = source.referer, !referer.isEmpty {
            headers["Referer"] = referer
            if headers["Origin"] == nil, let origin = originString(from: referer) {
                headers["Origin"] = origin
            }
        }
        return headers
    }

    private func filteredResponseHeaders(
        from response: HTTPURLResponse,
        fallbackContentType: String
    ) -> [String: String] {
        var headers: [String: String] = [:]
        for name in ["Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "ETag", "Last-Modified"] {
            if let value = response.value(forHTTPHeaderField: name), !value.isEmpty {
                headers[name] = value
            }
        }
        headers["Content-Type"] = headers["Content-Type"] ?? fallbackContentType
        headers["Cache-Control"] = "no-store"
        return headers
    }

    private func shouldProxy(url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        let host = url.host?.lowercased() ?? ""
        return host != "127.0.0.1" && host != "localhost"
    }

    private func directPlaybackURL(for url: URL) -> URL {
        guard !isPlaylistURL(url),
              let upgradedURL = httpsURL(for: url) else {
            return url
        }
        return upgradedURL
    }

    private func httpsURL(for url: URL) -> URL? {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        return components.url
    }

    private func sourceByReplacingURL(_ source: VideoSource, with url: URL) -> VideoSource {
        VideoSource(
            url: url,
            quality: source.quality,
            pluginName: source.pluginName,
            referer: source.referer,
            headers: source.headers
        )
    }

    private func shouldRetryByUpgradingToHTTPS(error: Error, url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http" else { return false }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
            && nsError.code == NSURLErrorAppTransportSecurityRequiresSecureConnection
    }

    private func isPlaylistURL(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        return path.contains(".m3u8") || value.contains("m3u8") || path.contains("manifest") || path.contains("playlist")
    }

    private func guessContentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8":
            return "application/vnd.apple.mpegurl"
        case "ts":
            return "video/mp2t"
        case "m4s":
            return "video/iso.segment"
        case "mp4", "m4v", "mov":
            return "video/mp4"
        case "m4a":
            return "audio/mp4"
        case "key":
            return "application/octet-stream"
        default:
            return "application/octet-stream"
        }
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
}

private final class LocalHLSProxyHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let proxy: LocalHLSProxy
    private var requestHead: HTTPRequestHead?
    private var body: ByteBuffer?

    init(proxy: LocalHLSProxy) {
        self.proxy = proxy
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch Self.unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head
            body = nil
        case .body(var buffer):
            if body == nil {
                body = buffer
            } else {
                body?.writeBuffer(&buffer)
            }
        case .end:
            guard let requestHead else { return }
            let proxy = proxy
            let body = body
            let loopBoundContext = context.loopBound
            Task {
                let response = await proxy.route(head: requestHead, body: body)
                loopBoundContext.eventLoop.execute {
                    Self.write(response: response, for: requestHead, context: loopBoundContext.value)
                }
            }
        }
    }

    private static func write(
        response: LocalProxyResponse,
        for requestHead: HTTPRequestHead,
        context: ChannelHandlerContext
    ) {
        var headers = NIOHTTP1.HTTPHeaders()
        for (name, value) in response.headers {
            headers.add(name: name, value: value)
        }
        headers.replaceOrAdd(name: "Connection", value: "close")

        let status = HTTPResponseStatus(statusCode: response.statusCode)
        let head = HTTPResponseHead(version: requestHead.version, status: status, headers: headers)
        context.write(Self.wrapOutboundOut(.head(head)), promise: nil)

        if requestHead.method != .HEAD, !response.body.isEmpty {
            var buffer = context.channel.allocator.buffer(capacity: response.body.count)
            buffer.writeBytes(response.body)
            context.write(Self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }

        context.writeAndFlush(Self.wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}

private struct LocalProxyResource {
    let url: URL
    let headers: [String: String]
    let sourcePage: String?
}

private struct LocalProxyResponse {
    let statusCode: Int
    var headers: [String: String]
    let body: Data

    init(statusCode: Int, headers: [String: String] = [:], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        if self.headers["Content-Length"] == nil {
            self.headers["Content-Length"] = "\(body.count)"
        }
    }

    init(statusCode: Int, headers: [String: String] = [:], bodyText: String) {
        var responseHeaders = headers
        responseHeaders["Content-Type"] = responseHeaders["Content-Type"] ?? "text/plain; charset=utf-8"
        self.init(statusCode: statusCode, headers: responseHeaders, body: Data(bodyText.utf8))
    }
}

enum LocalHLSProxyError: LocalizedError {
    case notRunning
    case invalidLocalURL
    case invalidResponse
    case upstreamStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "本地播放代理未启动"
        case .invalidLocalURL:
            return "本地播放代理地址无效"
        case .invalidResponse:
            return "远端媒体响应无效"
        case .upstreamStatus(let statusCode):
            return "远端媒体请求失败: \(statusCode)"
        }
    }
}
