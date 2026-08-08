//
//  APIClient.swift
//  KazumiTV
//
//  HTTP Client using URLSession
//

import Foundation

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.httpCookieStorage = .shared
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Request Methods

    func get(url: URL, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await TransientNetworkRetry.data(
            session: session,
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        return (data, httpResponse)
    }

    func post(url: URL, body: [String: Any], headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = jsonData

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        return (data, httpResponse)
    }

    func fetchHTML(url: URL, headers: [String: String] = [:], timeout: TimeInterval? = nil) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let timeout {
            request.timeoutInterval = timeout
        }
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.15.3 (KHTML, like Gecko) Version/17.0 Safari/605.15.3", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await TransientNetworkRetry.data(
            session: session,
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if let signal = WebChallengeDetector.detect(data: data, response: httpResponse) {
            throw APIError.webChallenge(signal)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let html = Self.htmlString(from: data) else {
            throw APIError.decodingError
        }

        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.emptyHTML
        }

        return html
    }

    func postFormHTML(url: URL, form: [String: String], headers: [String: String] = [:]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.15.3 (KHTML, like Gecko) Version/17.0 Safari/605.15.3", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let body = form.map { key, value in
            "\(percentEncodeFormComponent(key))=\(percentEncodeFormComponent(value))"
        }
        .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if let signal = WebChallengeDetector.detect(data: data, response: httpResponse) {
            throw APIError.webChallenge(signal)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let html = Self.htmlString(from: data) else {
            throw APIError.decodingError
        }

        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIError.emptyHTML
        }

        return html
    }

    private static func htmlString(from data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\""),
           trimmed.hasSuffix("\""),
           let jsonData = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: jsonData),
           decoded.localizedCaseInsensitiveContains("<html") || decoded.localizedCaseInsensitiveContains("<!doctype") {
            return decoded
        }

        return raw
    }

    private func percentEncodeFormComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    func download(url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await TransientNetworkRetry.data(
            session: session,
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        return data
    }

    // MARK: - JSON Decoding

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        return try decoder.decode(type, from: data)
    }
}

enum TransientNetworkRetry {
    static func data(
        session: URLSession,
        for request: URLRequest,
        maxAttempts: Int = 2
    ) async throws -> (Data, URLResponse) {
        let attempts = max(1, maxAttempts)
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                return try await session.data(for: request)
            } catch {
                lastError = error
                guard attempt < attempts, shouldRetry(error) else {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 350_000_000)
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    static func shouldRetry(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain,
              nsError.userInfo[NSURLErrorFailingURLPeerTrustErrorKey] == nil else {
            return false
        }

        let code = URLError.Code(rawValue: nsError.code)
        return [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .secureConnectionFailed,
        ].contains(code)
    }
}

// MARK: - API Error
enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError
    case networkError(Error)
    case emptyHTML
    case webChallenge(WebChallengeSignal)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP Error: \(statusCode)"
        case .decodingError:
            return "Failed to decode response"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .emptyHTML:
            return "来源返回空页面"
        case .webChallenge(let signal):
            switch signal.kind {
            case .challenge:
                return "\(signal.displayName) 需要真实浏览器验证"
            case .captcha:
                return "\(signal.displayName) 需要验证码验证"
            }
        }
    }
}

// MARK: - HTTP Headers Helper
struct HTTPHeaders {
    static let defaultHeaders = [
        "User-Agent": "KazumiTV/1.0",
        "Accept": "application/json"
    ]

    static func bangumiHeaders() -> [String: String] {
        return [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.15.3 (KHTML, like Gecko) Version/17.0 Safari/605.15.3",
            "Accept": "application/json"
        ]
    }
}
