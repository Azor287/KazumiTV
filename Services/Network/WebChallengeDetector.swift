//
//  WebChallengeDetector.swift
//  KazumiTV
//

import Foundation

struct WebChallengeSignal: Equatable {
    enum Kind {
        case challenge
        case captcha
    }

    let kind: Kind
    let vendor: String?

    var displayName: String {
        vendor ?? "真实浏览器验证"
    }
}

enum WebChallengeDetector {
    static func detect(data: Data, response: HTTPURLResponse) -> WebChallengeSignal? {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String else { return }
            result[key.lowercased()] = String(describing: item.value).lowercased()
        }

        if headers["cf-mitigated"] == "challenge" {
            return WebChallengeSignal(kind: .challenge, vendor: "Cloudflare")
        }

        let text = String(data: data.prefix(256 * 1024), encoding: .utf8)?
            .lowercased()
            ?? String(data: data.prefix(256 * 1024), encoding: .isoLatin1)?.lowercased()
            ?? ""
        guard !text.isEmpty else { return nil }

        if text.contains("g-recaptcha") || text.contains("recaptcha") {
            return WebChallengeSignal(kind: .captcha, vendor: "reCAPTCHA")
        }

        if text.contains("turnstile") || text.contains("cf-chl") || text.contains("cf_clearance") {
            return WebChallengeSignal(kind: .challenge, vendor: "Cloudflare")
        }

        if text.contains("datadome") || headers.values.contains(where: { $0.contains("datadome") }) {
            if text.contains("captcha") {
                return WebChallengeSignal(kind: .captcha, vendor: "DataDome")
            }
            return WebChallengeSignal(kind: .challenge, vendor: "DataDome")
        }

        if text.contains("checking your browser") || text.contains("just a moment") {
            return WebChallengeSignal(kind: .challenge, vendor: "Cloudflare")
        }

        if text.contains("device check") || text.contains("browser verification") {
            return WebChallengeSignal(kind: .challenge, vendor: nil)
        }

        return nil
    }
}
