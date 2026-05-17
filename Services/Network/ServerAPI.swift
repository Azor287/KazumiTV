//
//  ServerAPI.swift
//  KazumiTV
//
//  外部后备解析服务 API - 仅在原生解析失败且用户启用时获取最终视频 URL
//

import Foundation

actor ServerAPI {
    static let shared = ServerAPI()

    private let scrapeTimeout: TimeInterval = 180
    private let healthCheckTimeout: TimeInterval = 8
    private let playbackUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"

    // 外部后备服务地址 - 从设置中加载
    private var serverBaseURL: String {
        normalizedServerBaseURL(SettingsRepository.shared.serverProxyURL)
    }

    private init() {}

    private func normalizedServerBaseURL(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            normalized = "http://127.0.0.1:5001"
        }

        normalized = normalized
            .replacingOccurrences(of: "http://localhost", with: "http://127.0.0.1")
            .replacingOccurrences(of: "https://localhost", with: "https://127.0.0.1")

        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        return normalized
    }

    // MARK: - 视频抓取

    /// 从外部后备服务抓取最终视频 URL
    /// - Parameters:
    ///   - url: 目标页面 URL
    ///   - plugin: 插件名称 (age, dm84, aafun, default)
    /// - Returns: 视频源信息
    func scrapeVideo(url: String, plugin: String = "default") async throws -> VideoSource {
        print("ServerAPI: 开始外部后备解析, URL: \(url), 插件: \(plugin)")
        print("ServerAPI: 后备服务地址: \(serverBaseURL)")

        guard var components = URLComponents(string: "\(serverBaseURL)/scrape") else {
            throw ServerAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "plugin", value: plugin)
        ]

        guard let requestURL = components.url else {
            print("ServerAPI: 无效的请求URL")
            throw ServerAPIError.invalidURL
        }

        print("ServerAPI: 请求URL: \(requestURL.absoluteString)")

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = scrapeTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServerAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw ServerAPIError.videoNotFound
            }
            throw ServerAPIError.serverError(httpResponse.statusCode)
        }

        let result = try JSONDecoder().decode(ScrapeResponse.self, from: data)

        if result.success, let videoURL = result.url, let videoSourceURL = URL(string: videoURL) {
            let sourcePage = result.sourcePage ?? url
            let referer = result.referer ?? sourcePage
            print("ServerAPI: 外部后备解析得到远端播放URL: \(videoSourceURL.absoluteString)")
            return VideoSource(
                url: videoSourceURL,
                quality: result.quality ?? "默认",
                pluginName: result.plugin ?? plugin,
                referer: referer,
                headers: playbackHeaders(referer: referer)
            )
        } else if result.success {
            throw ServerAPIError.invalidURL
        } else {
            throw ServerAPIError.scrapeFailed(result.error ?? "未知错误")
        }
    }

    /// 使用真实浏览器渲染方式抓取视频（需要外部服务中的 Playwright）
    /// - Parameter url: 目标页面 URL
    /// - Returns: 视频源信息
    func scrapeVideoWithJS(url: String) async throws -> VideoSource {
        guard var components = URLComponents(string: "\(serverBaseURL)/scrape_js") else {
            throw ServerAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: url)
        ]

        guard let requestURL = components.url else {
            throw ServerAPIError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = scrapeTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServerAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw ServerAPIError.videoNotFound
            }
            throw ServerAPIError.serverError(httpResponse.statusCode)
        }

        let result = try JSONDecoder().decode(ScrapeResponse.self, from: data)

        if result.success, let videoURL = result.url, let videoSourceURL = URL(string: videoURL) {
            let sourcePage = result.sourcePage ?? url
            let referer = result.referer ?? sourcePage
            print("ServerAPI: 外部浏览器后备解析得到远端播放URL: \(videoSourceURL.absoluteString)")
            return VideoSource(
                url: videoSourceURL,
                quality: "默认",
                pluginName: "js_render",
                referer: referer,
                headers: playbackHeaders(referer: referer)
            )
        } else if result.success {
            throw ServerAPIError.invalidURL
        } else {
            throw ServerAPIError.scrapeFailed(result.error ?? "未知错误")
        }
    }

    /// 健康检查
    func healthCheck() async -> Bool {
        let healthURL = "\(serverBaseURL)/health"
        print("ServerAPI: 健康检查 URL: \(healthURL)")
        guard let url = URL(string: healthURL) else {
            print("ServerAPI: 无效的健康检查URL")
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = healthCheckTimeout
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("ServerAPI: 无效的响应")
                return false
            }
            print("ServerAPI: 健康检查状态码: \(httpResponse.statusCode)")
            return httpResponse.statusCode == 200
        } catch {
            print("ServerAPI: 健康检查错误: \(error)")
            return false
        }
    }

    func fetchRuleRepositoryIndex() async throws -> Data {
        try await fetchServerData(path: "rules/index", queryItems: [])
    }

    func fetchRuleRepositoryPlugin(name: String) async throws -> Data {
        try await fetchServerData(path: "rules/plugin", queryItems: [
            URLQueryItem(name: "name", value: name)
        ])
    }

    private func fetchServerData(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        guard var components = URLComponents(string: "\(serverBaseURL)/\(path)") else {
            throw ServerAPIError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw ServerAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = scrapeTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServerAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ServerAPIError.serverError(httpResponse.statusCode)
        }

        return data
    }

    private func playbackHeaders(referer: String?) -> [String: String] {
        var headers = [
            "User-Agent": playbackUserAgent,
            "Accept": "*/*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
        ]

        if let referer, !referer.isEmpty {
            headers["Referer"] = referer
            if let origin = originString(from: referer) {
                headers["Origin"] = origin
            }
        }

        return headers
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

// MARK: - Response Types

private struct ScrapeResponse: Decodable {
    let success: Bool
    let url: String?
    let quality: String?
    let plugin: String?
    let referer: String?
    let sourcePage: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case url
        case quality
        case plugin
        case referer
        case sourcePage = "source_page"
        case error
    }
}

// MARK: - Errors

enum ServerAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case videoNotFound
    case serverError(Int)
    case scrapeFailed(String)
    case serverNotAvailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的服务器 URL"
        case .invalidResponse:
            return "服务器响应无效"
        case .videoNotFound:
            return "服务器未找到视频"
        case .serverError(let code):
            return "服务器错误: \(code)"
        case .scrapeFailed(let msg):
            return "抓取失败: \(msg)"
        case .serverNotAvailable:
            return "服务器不可用"
        }
    }
}
