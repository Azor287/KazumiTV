//
//  URLLogSanitizer.swift
//  KazumiTV
//
//  Removes query strings and fragments before URLs are written to logs.
//

import Foundation

enum URLLogSanitizer {
    static func redacted(_ url: URL?) -> String {
        redacted(url?.absoluteString)
    }

    static func redacted(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "nil" }
        guard var components = URLComponents(string: value) else { return value }

        if components.query != nil {
            components.query = "redacted"
        }
        if components.fragment != nil {
            components.fragment = "redacted"
        }

        return components.string ?? value
    }
}
