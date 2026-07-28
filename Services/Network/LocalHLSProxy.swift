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
    private let mediaSession: URLSession
    private var resources: [String: LocalProxyResource] = [:]
    private var resourceTokensByKey: [String: String] = [:]
    private var channel: Channel?
    private var group: MultiThreadedEventLoopGroup?
    private var port: Int?

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        configuration.httpShouldSetCookies = false
        configuration.connectionProxyDictionary = [:]
        self.mediaSession = URLSession(configuration: configuration)
    }

    func proxiedSource(for source: VideoSource) throws -> VideoSource {
        let playbackURL = source.url
        let playbackSource = source

        guard shouldProxy(url: playbackURL) else {
            return playbackSource
        }

        try startIfNeeded()

        guard let port else {
            throw LocalHLSProxyError.notRunning
        }

        resetResources()

        let route = isPlaylistURL(playbackURL) ? "playlist" : "media"
        let token = register(
            url: playbackURL,
            headers: playbackHeaders(for: playbackSource),
            sourcePage: playbackSource.referer
        )
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

    fileprivate func respond(
        head: HTTPRequestHead,
        body: ByteBuffer?,
        writeResponse: @escaping (LocalProxyResponse) async -> Void,
        writeStreamHead: @escaping (Int, [String: String]) async throws -> Void,
        writeStreamBody: @escaping (Data) async throws -> Void,
        finishStream: @escaping () async -> Void
    ) async {
        guard head.method == .GET || head.method == .HEAD else {
            await writeResponse(LocalProxyResponse(statusCode: 405, headers: ["Allow": "GET, HEAD"], body: Data()))
            return
        }

        guard let components = URLComponents(string: "http://127.0.0.1\(head.uri)") else {
            await writeResponse(LocalProxyResponse(statusCode: 400, bodyText: "Bad request"))
            return
        }

        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count == 2 else {
            await writeResponse(LocalProxyResponse(statusCode: 404, bodyText: "Not found"))
            return
        }

        let route = parts[0]
        let token = parts[1]
        guard let resource = resource(for: token) else {
            await writeResponse(LocalProxyResponse(statusCode: 404, bodyText: "Unknown media token"))
            return
        }

        var didStartStream = false
        do {
            switch route {
            case "playlist":
                let response = try await playlistResponse(for: resource, requestHead: head)
                await writeResponse(response)
            case "media":
                try await streamMediaResponse(
                    for: resource,
                    requestHead: head,
                    writeHead: { statusCode, headers in
                        didStartStream = true
                        try await writeStreamHead(statusCode, headers)
                    },
                    writeBody: writeStreamBody,
                    finish: finishStream
                )
            default:
                await writeResponse(LocalProxyResponse(statusCode: 404, bodyText: "Not found"))
            }
        } catch {
            print("LocalHLSProxy: request failed url=\(redactedURLString(resource.url)) error=\(error.localizedDescription)")
            if didStartStream {
                await finishStream()
            } else {
                await writeResponse(LocalProxyResponse(statusCode: 502, bodyText: error.localizedDescription))
            }
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
        let resourceKey = cacheKey(
            url: url,
            headers: headers,
            sourcePage: sourcePage
        )
        let resource = LocalProxyResource(
            url: url,
            headers: cookieJar.headersByAddingCookies(headers, for: url),
            sourcePage: sourcePage
        )

        lock.lock()
        if let existingToken = resourceTokensByKey[resourceKey] {
            lock.unlock()
            return existingToken
        }

        let token = UUID().uuidString
        resources[token] = resource
        resourceTokensByKey[resourceKey] = token
        lock.unlock()

        return token
    }

    private func resetResources() {
        lock.lock()
        resources.removeAll()
        resourceTokensByKey.removeAll()
        lock.unlock()
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

        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            print("LocalHLSProxy: upstream did not return HLS playlist status=\(response.statusCode) url=\(redactedURLString(resource.url)) contentType=\(response.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
            return LocalProxyResponse(statusCode: 502, bodyText: "远端没有返回 HLS 播放列表")
        }
        let inspection = HLSPlaylistInspector.inspect(text, url: resource.url)
        guard inspection.isPlaylist else {
            print("LocalHLSProxy: upstream did not return HLS playlist status=\(response.statusCode) url=\(redactedURLString(resource.url)) contentType=\(response.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
            return LocalProxyResponse(statusCode: 502, bodyText: "远端没有返回 HLS 播放列表")
        }
        guard inspection.isLikelyPlayable else {
            print("LocalHLSProxy: upstream returned placeholder HLS url=\(redactedURLString(resource.url)) reason=\(inspection.reason ?? "unplayable playlist")")
            return LocalProxyResponse(statusCode: 502, bodyText: "远端返回占位播放列表")
        }

        let rewritten = rewritePlaylist(text, playlistURL: response.url ?? resource.url, resource: resource)
        let rewrittenData = Data(rewritten.utf8)
        let body = requestHead.method == .HEAD ? Data() : rewrittenData
        return LocalProxyResponse(
            statusCode: 200,
            headers: [
                "Content-Type": "application/vnd.apple.mpegurl; charset=utf-8",
                "Content-Length": "\(rewrittenData.count)",
                "Cache-Control": "no-cache",
                "Access-Control-Allow-Origin": "*"
            ],
            body: body
        )
    }

    private func streamMediaResponse(
        for resource: LocalProxyResource,
        requestHead: HTTPRequestHead,
        writeHead: (Int, [String: String]) async throws -> Void,
        writeBody: (Data) async throws -> Void,
        finish: () async -> Void
    ) async throws {
        let request = remoteRequest(
            resource: resource,
            requestHead: requestHead,
            accept: "*/*",
            includeRange: true,
            upstreamMethod: "GET"
        )

        let bytesAndResponse: (URLSession.AsyncBytes, URLResponse)
        do {
            bytesAndResponse = try await mediaSession.bytes(for: request)
        } catch {
            guard shouldRetryByUpgradingToHTTPS(error: error, url: resource.url),
                  let upgradedURL = httpsURL(for: resource.url) else {
                throw error
            }
            print("LocalHLSProxy: retrying insecure media over HTTPS url=\(redactedURLString(upgradedURL))")
            let upgradedResource = LocalProxyResource(
                url: upgradedURL,
                headers: resource.headers,
                sourcePage: resource.sourcePage
            )
            try await streamMediaResponse(
                for: upgradedResource,
                requestHead: requestHead,
                writeHead: writeHead,
                writeBody: writeBody,
                finish: finish
            )
            return
        }

        let (bytes, response) = bytesAndResponse
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalHLSProxyError.invalidResponse
        }
        cookieJar.storeCookies(from: httpResponse, for: resource.url)
        if let signal = WebChallengeDetector.detect(data: Data(), response: httpResponse) {
            throw LocalHLSProxyError.webChallenge(signal)
        }
        guard (200...399).contains(httpResponse.statusCode) else {
            print("LocalHLSProxy: upstream HTTP \(httpResponse.statusCode) url=\(redactedURLString(resource.url)) contentType=\(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
            throw LocalHLSProxyError.upstreamStatus(httpResponse.statusCode)
        }
        guard !isHTMLLikeContentType(httpResponse) else {
            print("LocalHLSProxy: upstream returned HTML for media url=\(redactedURLString(resource.url)) contentType=\(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
            throw LocalHLSProxyError.invalidResponse
        }

        var headers = filteredResponseHeaders(from: httpResponse, fallbackContentType: guessContentType(for: resource.url))
        headers["Accept-Ranges"] = headers["Accept-Ranges"] ?? "bytes"
        headers["Access-Control-Allow-Origin"] = "*"

        try await writeHead(httpResponse.statusCode, headers)
        guard requestHead.method != .HEAD else {
            await finish()
            return
        }

        var buffer: [UInt8] = []
        buffer.reserveCapacity(64 * 1024)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try await writeBody(Data(buffer))
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            try await writeBody(Data(buffer))
        }
        await finish()
    }

    private func remoteRequest(
        resource: LocalProxyResource,
        requestHead: HTTPRequestHead,
        accept: String,
        includeRange: Bool,
        upstreamMethod: String? = nil
    ) -> URLRequest {
        var request = URLRequest(url: resource.url)
        request.httpMethod = upstreamMethod ?? (requestHead.method == .HEAD ? "HEAD" : "GET")
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

        return request
    }

    private func fetchRemote(
        resource: LocalProxyResource,
        requestHead: HTTPRequestHead,
        accept: String,
        includeRange: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        let request = remoteRequest(
            resource: resource,
            requestHead: requestHead,
            accept: accept,
            includeRange: includeRange,
            upstreamMethod: "GET"
        )

        let dataAndResponse: (Data, URLResponse)
        do {
            dataAndResponse = try await mediaSession.data(for: request)
        } catch {
            guard shouldRetryByUpgradingToHTTPS(error: error, url: resource.url),
                  let upgradedURL = httpsURL(for: resource.url) else {
                throw error
            }
            print("LocalHLSProxy: retrying insecure media over HTTPS url=\(redactedURLString(upgradedURL))")
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
        if let signal = WebChallengeDetector.detect(data: data, response: httpResponse) {
            throw LocalHLSProxyError.webChallenge(signal)
        }
        guard (200...399).contains(httpResponse.statusCode) else {
            print("LocalHLSProxy: upstream HTTP \(httpResponse.statusCode) url=\(redactedURLString(resource.url)) contentType=\(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
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
        if headers["Content-Type"]?.lowercased().contains("image/gif") == true,
           fallbackContentType == "video/mp2t" {
            headers["Content-Type"] = fallbackContentType
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

    private func isPlaylistURL(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        return value.contains(".m3u8")
            || path.hasSuffix("/manifest")
            || path.hasSuffix("/playlist")
    }

    private func isHTMLLikeContentType(_ response: HTTPURLResponse) -> Bool {
        let contentType = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        return contentType.contains("text/html") || contentType.contains("application/xhtml")
    }

    private func cacheKey(
        url: URL,
        headers: [String: String],
        sourcePage: String?
    ) -> String {
        let headerKey = headers
            .sorted { lhs, rhs in lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending }
            .map { key, value in "\(key.lowercased())=\(value)" }
            .joined(separator: "&")
        return "\(url.absoluteString)|\(sourcePage ?? "")|\(headerKey)"
    }

    private func guessContentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8":
            return "application/vnd.apple.mpegurl"
        case "ts":
            return "video/mp2t"
        case "gif":
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

    private func redactedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.host ?? "unknown"
        }
        components.query = components.queryItems?.isEmpty == false ? "<redacted>" : nil
        components.fragment = nil
        return components.string ?? "\(url.scheme ?? "https")://\(url.host ?? "unknown")\(url.path)"
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
            func writeOnEventLoop(_ operation: @escaping (ChannelHandlerContext) -> EventLoopFuture<Void>) async throws {
                try await withCheckedThrowingContinuation { continuation in
                    loopBoundContext.eventLoop.execute {
                        operation(loopBoundContext.value).whenComplete { result in
                            continuation.resume(with: result)
                        }
                    }
                }
            }
            Task {
                await proxy.respond(
                    head: requestHead,
                    body: body,
                    writeResponse: { response in
                        try? await writeOnEventLoop { context in
                            Self.writeFuture(response: response, for: requestHead, context: context)
                        }
                    },
                    writeStreamHead: { statusCode, headers in
                        try await writeOnEventLoop { context in
                            Self.writeStreamHeadFuture(
                                statusCode: statusCode,
                                headers: headers,
                                for: requestHead,
                                context: context
                            )
                        }
                    },
                    writeStreamBody: { data in
                        try await writeOnEventLoop { context in
                            Self.writeStreamBodyFuture(data: data, context: context)
                        }
                    },
                    finishStream: {
                        try? await writeOnEventLoop { context in
                            Self.finishStreamFuture(context: context)
                        }
                    }
                )
            }
        }
    }

    private static func write(
        response: LocalProxyResponse,
        for requestHead: HTTPRequestHead,
        context: ChannelHandlerContext
    ) {
        _ = writeFuture(response: response, for: requestHead, context: context)
    }

    private static func writeFuture(
        response: LocalProxyResponse,
        for requestHead: HTTPRequestHead,
        context: ChannelHandlerContext
    ) -> EventLoopFuture<Void> {
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

        let promise = context.eventLoop.makePromise(of: Void.self)
        context.writeAndFlush(Self.wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close().whenComplete { result in
                promise.completeWith(result)
            }
        }
        return promise.futureResult
    }

    private static func writeStreamHeadFuture(
        statusCode: Int,
        headers responseHeaders: [String: String],
        for requestHead: HTTPRequestHead,
        context: ChannelHandlerContext
    ) -> EventLoopFuture<Void> {
        var headers = NIOHTTP1.HTTPHeaders()
        for (name, value) in responseHeaders {
            headers.add(name: name, value: value)
        }
        headers.replaceOrAdd(name: "Connection", value: "close")

        let status = HTTPResponseStatus(statusCode: statusCode)
        let head = HTTPResponseHead(version: requestHead.version, status: status, headers: headers)
        return context.writeAndFlush(Self.wrapOutboundOut(.head(head)))
    }

    private static func writeStreamBodyFuture(
        data: Data,
        context: ChannelHandlerContext
    ) -> EventLoopFuture<Void> {
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        return context.writeAndFlush(Self.wrapOutboundOut(.body(.byteBuffer(buffer))))
    }

    private static func finishStreamFuture(context: ChannelHandlerContext) -> EventLoopFuture<Void> {
        let promise = context.eventLoop.makePromise(of: Void.self)
        context.writeAndFlush(Self.wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close().whenComplete { result in
                promise.completeWith(result)
            }
        }
        return promise.futureResult
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
    case webChallenge(WebChallengeSignal)

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
        case .webChallenge(let signal):
            switch signal.kind {
            case .challenge:
                return "\(signal.displayName) 要求真实浏览器验证"
            case .captcha:
                return "\(signal.displayName) 要求验证码验证"
            }
        }
    }
}
