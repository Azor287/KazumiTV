//
//  PluginRule.swift
//  KazumiTV
//
//  Plugin Rule Model - XPath-based scraping rules
//

import Foundation

enum PluginAPIValue: Codable, Equatable, Hashable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return ""
        }
    }
}

struct PluginAPIRequest: Codable, Equatable, Hashable {
    let method: String
    let url: String
    let query: [String: PluginAPIValue]?
}

struct PluginSearchAPIConfig: Codable, Equatable, Hashable {
    let request: PluginAPIRequest
    let listPath: String
    let namePath: String
    let sourcePath: String
}

struct PluginEpisodePageConfig: Codable, Equatable, Hashable {
    let url: String
    let query: [String: PluginAPIValue]?
}

struct PluginChapterAPIConfig: Codable, Equatable, Hashable {
    let request: PluginAPIRequest
    let format: String?
    let roadsPath: String
    let roadNamePath: String
    let episodesPath: String
    let episodeNamePath: String
    let episodeUrlPath: String
    let variables: [String: String]?
    let episodePage: PluginEpisodePageConfig
}

struct PluginRule: Codable, Identifiable, Equatable, Hashable {
    let api: String
    let type: String
    let name: String
    let version: String
    let muliSources: Bool
    let useWebview: Bool
    let useNativePlayer: Bool
    let usePost: Bool?
    let useLegacyParser: Bool?
    let userAgent: String
    let baseURL: String
    let searchURL: String
    let searchList: String
    let searchName: String
    let searchResult: String
    let chapterRoads: String
    let chapterResult: String
    let referer: String?
    let adBlocker: Bool?
    let antiCrawlerConfig: AntiCrawlerConfig?
    let sourceSearch: PluginSearchCapability?
    let capability: PluginCapability?
    let fallback: PluginFallbackCapability?
    let observability: PluginObservability?
    var searchMode: String? = nil
    var chapterMode: String? = nil
    var searchApiConfig: PluginSearchAPIConfig? = nil
    var chapterApiConfig: PluginChapterAPIConfig? = nil
    var nativeResolver: String? = nil
    var mediaPatterns: [String]? = nil
    var iframePatterns: [String]? = nil
    var playbackHeaders: [String: String]? = nil

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case api, type, name, version, muliSources, useWebview, useNativePlayer
        case usePost, useLegacyParser
        case userAgent, baseURL, searchURL, searchList, searchName, searchResult
        case chapterRoads, chapterResult, referer, adBlocker, antiCrawlerConfig
        case sourceSearch = "search", capability, fallback, observability
        case searchMode, chapterMode, searchApiConfig, chapterApiConfig
        case nativeResolver, mediaPatterns, iframePatterns, playbackHeaders
    }

    func buildSearchURL(keyword: String) -> String {
        var url = searchURL
        if url.contains("@keyword") {
            let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
            url = url.replacingOccurrences(of: "@keyword", with: encodedKeyword)
        }
        return url
    }

    static func template() -> PluginRule {
        PluginRule(
            api: "6",
            type: "anime",
            name: "",
            version: "1.0",
            muliSources: true,
            useWebview: true,
            useNativePlayer: true,
            usePost: false,
            useLegacyParser: false,
            userAgent: "",
            baseURL: "",
            searchURL: "",
            searchList: "",
            searchName: "",
            searchResult: "",
            chapterRoads: "",
            chapterResult: "",
            referer: "",
            adBlocker: false,
            antiCrawlerConfig: nil,
            sourceSearch: nil,
            capability: nil,
            fallback: nil,
            observability: nil
        )
    }

    var shareURL: String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return "kazumi://\(Data(json.utf8).base64EncodedString())"
    }

    static func decodeShareURL(_ value: String) throws -> PluginRule {
        guard value.hasPrefix("kazumi://") else {
            throw PluginError.invalidSharePayload
        }

        let raw = String(value.dropFirst("kazumi://".count))
        guard let data = Data(base64Encoded: raw) else {
            throw PluginError.invalidSharePayload
        }

        return try JSONDecoder().decode(PluginRule.self, from: data)
    }
}

struct PluginRepositoryItem: Decodable, Identifiable, Hashable {
    let name: String
    let version: String
    let useNativePlayer: Bool
    let author: String
    let lastUpdate: Int
    let antiCrawlerEnabled: Bool

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, version, useNativePlayer, author, lastUpdate
        case antiCrawlerEnabled, antiCrawlerConfig
    }

    init(
        name: String,
        version: String,
        useNativePlayer: Bool,
        author: String,
        lastUpdate: Int,
        antiCrawlerEnabled: Bool
    ) {
        self.name = name
        self.version = version
        self.useNativePlayer = useNativePlayer
        self.author = author
        self.lastUpdate = lastUpdate
        self.antiCrawlerEnabled = antiCrawlerEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        useNativePlayer = try container.decode(Bool.self, forKey: .useNativePlayer)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        lastUpdate = try container.decodeIfPresent(Int.self, forKey: .lastUpdate) ?? 0

        if let direct = try container.decodeIfPresent(Bool.self, forKey: .antiCrawlerEnabled) {
            antiCrawlerEnabled = direct
        } else if let config = try container.decodeIfPresent(RepositoryAntiCrawlerConfig.self, forKey: .antiCrawlerConfig) {
            antiCrawlerEnabled = config.enabled
        } else {
            antiCrawlerEnabled = false
        }
    }

    private struct RepositoryAntiCrawlerConfig: Codable {
        let enabled: Bool
    }
}

struct AntiCrawlerConfig: Codable, Equatable, Hashable {
    let type: String?
    let delay: Int?
    let maxRetries: Int?
}

// MARK: - Chapter/Episode Road
struct ChapterRoad: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let episodes: [EpisodeItem]

    struct EpisodeItem: Identifiable, Equatable, Hashable {
        let id: String
        let name: String
        let src: String
        let episode: Int
    }
}

extension ChapterRoad {
    static let sample = ChapterRoad(
        id: "road-1",
        name: "主线路",
        episodes: [
            EpisodeItem(id: "ep-1", name: "第1话", src: "https://example.com/1", episode: 1),
            EpisodeItem(id: "ep-2", name: "第2话", src: "https://example.com/2", episode: 2)
        ]
    )
}
