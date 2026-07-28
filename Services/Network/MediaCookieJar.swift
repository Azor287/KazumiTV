//
//  MediaCookieJar.swift
//  KazumiTV
//
//  Small in-memory cookie jar used by native video resolution and the local
//  playback proxy. It keeps source/player cookies on the Apple TV and injects
//  them into media requests without relying on external services.
//

import Foundation

final class MediaCookieJar {
    private let lock = NSLock()
    private var cookiesByKey: [String: HTTPCookie] = [:]

    func storeCookies(from response: HTTPURLResponse, for url: URL) {
        let headerFields = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String else { return }
            result[key] = String(describing: item.value)
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        guard !cookies.isEmpty else { return }

        lock.lock()
        for cookie in cookies {
            let key = storageKey(for: cookie)
            if isExpired(cookie) {
                cookiesByKey.removeValue(forKey: key)
            } else {
                cookiesByKey[key] = cookie
            }
        }
        lock.unlock()
    }

    func headersByAddingCookies(_ headers: [String: String], for url: URL) -> [String: String] {
        guard let cookieHeader = cookieHeader(for: url), !cookieHeader.isEmpty else {
            return headers
        }

        var result = headers
        if let existingKey = result.keys.first(where: { $0.caseInsensitiveCompare("Cookie") == .orderedSame }),
           let existing = result[existingKey],
           !existing.isEmpty {
            result[existingKey] = mergedCookieHeader(existing: existing, additional: cookieHeader)
        } else {
            result["Cookie"] = cookieHeader
        }
        return result
    }

    func cookieHeader(for url: URL) -> String? {
        let cookies = matchingCookies(for: url)
        guard !cookies.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    private func matchingCookies(for url: URL) -> [HTTPCookie] {
        lock.lock()
        let now = Date()
        var expiredKeys: [String] = []
        var matches: [HTTPCookie] = []

        for (key, cookie) in cookiesByKey {
            if let expiresDate = cookie.expiresDate, expiresDate <= now {
                expiredKeys.append(key)
                continue
            }
            if cookieMatches(cookie, url: url) {
                matches.append(cookie)
            }
        }

        for key in expiredKeys {
            cookiesByKey.removeValue(forKey: key)
        }
        lock.unlock()

        return matches.sorted { lhs, rhs in
            if lhs.path.count == rhs.path.count {
                return lhs.name < rhs.name
            }
            return lhs.path.count > rhs.path.count
        }
    }

    private func cookieMatches(_ cookie: HTTPCookie, url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let domain = cookie.domain.lowercased()
        let normalizedDomain = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        let domainMatches: Bool

        if domain.hasPrefix(".") {
            domainMatches = host == normalizedDomain || host.hasSuffix("." + normalizedDomain)
        } else {
            domainMatches = host == normalizedDomain
        }

        guard domainMatches else { return false }

        if cookie.isSecure, url.scheme?.lowercased() != "https" {
            return false
        }

        let requestPath = url.path.isEmpty ? "/" : url.path
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        guard requestPath.hasPrefix(cookiePath) else { return false }
        if cookiePath.hasSuffix("/") || requestPath.count == cookiePath.count {
            return true
        }
        let boundary = requestPath.index(requestPath.startIndex, offsetBy: cookiePath.count)
        return requestPath[boundary] == "/"
    }

    private func isExpired(_ cookie: HTTPCookie) -> Bool {
        guard let expiresDate = cookie.expiresDate else { return false }
        return expiresDate <= Date()
    }

    private func storageKey(for cookie: HTTPCookie) -> String {
        "\(cookie.domain.lowercased())|\(cookie.path)|\(cookie.name)"
    }

    private func mergedCookieHeader(existing: String, additional: String) -> String {
        let existingNames = Set(
            existing
                .split(separator: ";")
                .compactMap { item -> String? in
                    let parts = item.split(separator: "=", maxSplits: 1)
                    return parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
        )
        let additionalPairs = additional
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { pair in
                guard let name = pair.split(separator: "=", maxSplits: 1).first else { return false }
                return !existingNames.contains(String(name))
            }

        guard !additionalPairs.isEmpty else {
            return existing
        }
        return ([existing] + additionalPairs).joined(separator: "; ")
    }
}
