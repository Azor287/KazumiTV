//
//  SourceCapability.swift
//  KazumiTV
//

import Foundation

enum SourceCapabilityMode: String, Codable, Hashable {
    case native
    case needsJSLite = "needs-js-lite"
    case needsBrowser = "needs-browser"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = SourceCapabilityMode(rawValue: rawValue) ?? .unknown
    }
}

enum SourceCaptchaRisk: String, Codable, Hashable {
    case low
    case medium
    case high
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = SourceCaptchaRisk(rawValue: rawValue) ?? .unknown
    }
}

struct PluginSearchCapability: Codable, Equatable, Hashable {
    let supported: Bool?
    let weight: Double?
}

struct PluginCapability: Codable, Equatable, Hashable {
    let mode: SourceCapabilityMode?
    let needsJS: Bool?
    let needsBrowser: Bool?
    let captchaRisk: SourceCaptchaRisk?
    let loginRequired: Bool?
    let sessionImportSupported: Bool?
    let playback: [String]?
    let mediaHeaders: [String]?
    let stability: Double?
}

struct PluginFallbackCapability: Codable, Equatable, Hashable {
    let allowCompanionSessionBridge: Bool?
    let allowExternalResolver: Bool?
}

struct PluginObservability: Codable, Equatable, Hashable {
    let challengeMarkers: [String]?
    let expectedContentTypes: [String]?
}

struct SourcePlaybackCapability: Equatable, Hashable {
    let mode: SourceCapabilityMode
    let searchSupported: Bool
    let searchWeight: Double
    let stability: Double
    let captchaRisk: SourceCaptchaRisk
    let loginRequired: Bool
    let sessionImportSupported: Bool
    let allowExternalResolver: Bool

    var supportsLocalPlayback: Bool {
        mode == .native || mode == .needsJSLite
    }

    var requiresBrowserRuntime: Bool {
        mode == .needsBrowser || captchaRisk == .high
    }

    var badgeTitle: String? {
        if supportsLocalPlayback { return "本机" }
        if requiresBrowserRuntime { return "本机网页" }
        return nil
    }
}

enum SourceCapabilityRegistry {
    private static let builtInCapabilities: [String: SourcePlaybackCapability] = [
        "mxdm": SourcePlaybackCapability(
            mode: .native,
            searchSupported: true,
            searchWeight: 1.0,
            stability: 0.95,
            captchaRisk: .low,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: false
        ),
        "aafun": SourcePlaybackCapability(
            mode: .needsJSLite,
            searchSupported: true,
            searchWeight: 0.82,
            stability: 0.68,
            captchaRisk: .medium,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: false
        ),
        "gpjda": SourcePlaybackCapability(
            mode: .native,
            searchSupported: true,
            searchWeight: 0.80,
            stability: 0.72,
            captchaRisk: .medium,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: false
        ),
        "gugu3": SourcePlaybackCapability(
            mode: .needsJSLite,
            searchSupported: true,
            searchWeight: 0.74,
            stability: 0.62,
            captchaRisk: .medium,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: false
        ),
        "baimao": SourcePlaybackCapability(
            mode: .needsBrowser,
            searchSupported: true,
            searchWeight: 0.58,
            stability: 0.42,
            captchaRisk: .high,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: true
        ),
        "omofun03": SourcePlaybackCapability(
            mode: .needsBrowser,
            searchSupported: true,
            searchWeight: 0.52,
            stability: 0.40,
            captchaRisk: .high,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: true
        ),
        "enlie": SourcePlaybackCapability(
            mode: .unknown,
            searchSupported: true,
            searchWeight: 0.46,
            stability: 0.38,
            captchaRisk: .medium,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: true
        ),
        "7sefun": SourcePlaybackCapability(
            mode: .needsBrowser,
            searchSupported: true,
            searchWeight: 0.48,
            stability: 0.36,
            captchaRisk: .high,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: true
        ),
        "yishijie": SourcePlaybackCapability(
            mode: .needsBrowser,
            searchSupported: true,
            searchWeight: 0.44,
            stability: 0.34,
            captchaRisk: .high,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: true
        ),
        "age": SourcePlaybackCapability(
            mode: .needsJSLite,
            searchSupported: true,
            searchWeight: 0.45,
            stability: 0.45,
            captchaRisk: .medium,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: true
        ),
        "dm84": SourcePlaybackCapability(
            mode: .needsBrowser,
            searchSupported: true,
            searchWeight: 0.42,
            stability: 0.44,
            captchaRisk: .high,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: true
        ),
        "mwcy": SourcePlaybackCapability(
            mode: .needsBrowser,
            searchSupported: true,
            searchWeight: 0.32,
            stability: 0.28,
            captchaRisk: .high,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: true
        ),
        "lmm": SourcePlaybackCapability(
            mode: .needsBrowser,
            searchSupported: true,
            searchWeight: 0.30,
            stability: 0.28,
            captchaRisk: .high,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: true
        ),
        "xfdm": SourcePlaybackCapability(
            mode: .needsBrowser,
            searchSupported: true,
            searchWeight: 0.30,
            stability: 0.28,
            captchaRisk: .high,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: true
        ),
        "xfdmneo": SourcePlaybackCapability(
            mode: .unknown,
            searchSupported: true,
            searchWeight: 0.34,
            stability: 0.30,
            captchaRisk: .medium,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: true
        ),
        "girigirilove": SourcePlaybackCapability(
            mode: .needsBrowser,
            searchSupported: true,
            searchWeight: 0.28,
            stability: 0.24,
            captchaRisk: .high,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: true
        )
    ]

    static func capability(for plugin: PluginRule) -> SourcePlaybackCapability {
        let builtIn = capability(forPluginName: plugin.name)
        let declared = plugin.capability

        let mode = declared?.mode
            ?? (declared?.needsBrowser == true ? .needsBrowser : nil)
            ?? (declared?.needsJS == true ? .needsJSLite : nil)
            ?? builtIn.mode

        let captchaRisk = declared?.captchaRisk ?? (plugin.antiCrawlerConfig == nil ? builtIn.captchaRisk : .high)

        return SourcePlaybackCapability(
            mode: mode,
            searchSupported: plugin.sourceSearch?.supported ?? builtIn.searchSupported,
            searchWeight: plugin.sourceSearch?.weight ?? builtIn.searchWeight,
            stability: declared?.stability ?? builtIn.stability,
            captchaRisk: captchaRisk,
            loginRequired: declared?.loginRequired ?? builtIn.loginRequired,
            sessionImportSupported: declared?.sessionImportSupported ?? builtIn.sessionImportSupported,
            allowExternalResolver: plugin.fallback?.allowExternalResolver ?? builtIn.allowExternalResolver
        )
    }

    static func capability(forPluginName pluginName: String) -> SourcePlaybackCapability {
        builtInCapabilities[normalizedPluginName(pluginName)] ?? SourcePlaybackCapability(
            mode: .unknown,
            searchSupported: true,
            searchWeight: 0.35,
            stability: 0.35,
            captchaRisk: .unknown,
            loginRequired: false,
            sessionImportSupported: false,
            allowExternalResolver: true
        )
    }

    static func normalizedPluginName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension PluginRule {
    var playbackCapability: SourcePlaybackCapability {
        SourceCapabilityRegistry.capability(for: self)
    }
}
