//
//  DanDanPlayAPI.swift
//  KazumiTV
//
//  DanDanPlay Danmaku API
//

import Foundation
import CryptoKit

actor DanDanPlayAPI {
    static let shared = DanDanPlayAPI()

    private let api = APIClient.shared
    private let decoder = JSONDecoder()

    // API Endpoints
    private let dandanAPIDomain = "https://api.dandanplay.net"
    private let appIDInfoKey = "DANDANPLAY_APP_ID"
    private let appSecretInfoKey = "DANDANPLAY_APP_SECRET"

    private init() {
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Search

    /// Search for bangumi by name on DanDanPlay
    func searchBangumi(keyword: String) async throws -> [DanDanPlayBangumi] {
        let path = "/api/v2/search/anime"
        let url = try makeURL(
            path: path,
            queryItems: [URLQueryItem(name: "keyword", value: keyword)]
        )

        let (data, _) = try await api.get(url: url, headers: try signedHeaders(path: path))
        let response = try decoder.decode(DanDanPlaySearchResponse.self, from: data)
        try validate(response)
        return response.animes
    }

    // MARK: - Get Comments (Danmaku)

    /// Get danmaku comments for a bangumi episode
    /// - Parameters:
    ///   - bangumiId: DanDanPlay bangumi ID
    ///   - episode: Episode number (e.g., 1 for first episode)
    func getComments(bangumiId: Int, episode: Int) async throws -> [DanmakuItem] {
        guard bangumiId > 0, episode > 0 else { return [] }

        let episodeIDString = "\(bangumiId)\(String(format: "%04d", episode))"
        guard let episodeID = Int(episodeIDString) else {
            throw DanmakuAPIError.invalidEpisodeID
        }

        return try await getCommentsByEpisodeID(episodeID)
    }

    /// Get danmaku by Bangumi.tv ID
    func getCommentsByBgmId(bgmBangumiId: Int, episode: Int) async throws -> [DanmakuItem] {
        guard episode > 0 else { return [] }
        guard let bangumi = try await getBangumiInfoByBgmId(bgmBangumiId: bgmBangumiId) else {
            throw DanmakuAPIError.bangumiNotFound(bgmBangumiId)
        }

        return try await getComments(bangumiId: bangumi.id, episode: episode)
    }

    /// Get danmaku by DanDanPlay episode ID.
    func getCommentsByEpisodeID(_ episodeID: Int) async throws -> [DanmakuItem] {
        guard episodeID > 0 else { return [] }

        let path = "/api/v2/comment/\(episodeID)"
        let url = try makeURL(
            path: path,
            queryItems: [URLQueryItem(name: "withRelated", value: "true")]
        )
        let (data, _) = try await api.get(url: url, headers: try signedHeaders(path: path))
        let response = try decoder.decode(DanDanPlayResponse.self, from: data)
        return response.comments.map { DanmakuItem(from: $0) }
    }

    // MARK: - Get Bangumi Info

    /// Get DanDanPlay bangumi info by ID
    func getBangumiInfo(bangumiId: Int) async throws -> DanDanPlayBangumi? {
        let path = "/api/v2/bangumi/\(bangumiId)"
        let url = try makeURL(path: path)

        let (data, _) = try await api.get(url: url, headers: try signedHeaders(path: path))
        let response = try decoder.decode(DanDanPlayBangumiInfoResponse.self, from: data)
        try validate(response)
        return response.bangumi
    }

    /// Get DanDanPlay bangumi info by Bangumi.tv ID
    func getBangumiInfoByBgmId(bgmBangumiId: Int) async throws -> DanDanPlayBangumi? {
        let path = "/api/v2/bangumi/bgmtv/\(bgmBangumiId)"
        let url = try makeURL(path: path)

        let (data, _) = try await api.get(url: url, headers: try signedHeaders(path: path))
        let response = try decoder.decode(DanDanPlayBangumiInfoResponse.self, from: data)
        try validate(response)
        return response.bangumi
    }

    // MARK: - Request Helpers

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: dandanAPIDomain + path) else {
            throw APIError.invalidResponse
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidResponse
        }

        return url
    }

    private func signedHeaders(path: String) throws -> [String: String] {
        let credentials = try credentials()
        let timestamp = Int(Date().timeIntervalSince1970)
        let payload = "\(credentials.appID)\(timestamp)\(path)\(credentials.appSecret)"
        let signature = Data(SHA256.hash(data: Data(payload.utf8))).base64EncodedString()

        return [
            "User-Agent": "Mozilla/5.0 (Apple TV; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Referer": "",
            "X-Auth": "1",
            "X-AppId": credentials.appID,
            "X-Timestamp": "\(timestamp)",
            "X-Signature": signature
        ]
    }

    private func credentials() throws -> (appID: String, appSecret: String) {
        let bundle = Bundle.main
        let environment = ProcessInfo.processInfo.environment
        let bundleAppID = sanitizedCredential(bundle.object(forInfoDictionaryKey: appIDInfoKey) as? String ?? "")
        let bundleAppSecret = sanitizedCredential(bundle.object(forInfoDictionaryKey: appSecretInfoKey) as? String ?? "")
        let environmentAppID = sanitizedCredential(environment[appIDInfoKey] ?? "")
        let environmentAppSecret = sanitizedCredential(environment[appSecretInfoKey] ?? "")
        let appID = bundleAppID.isEmpty ? environmentAppID : bundleAppID
        let appSecret = bundleAppSecret.isEmpty ? environmentAppSecret : bundleAppSecret

        guard !appID.isEmpty, !appSecret.isEmpty else {
            throw DanmakuAPIError.credentialsMissing
        }

        return (appID, appSecret)
    }

    private func sanitizedCredential(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || (trimmed.hasPrefix("$(") && trimmed.hasSuffix(")")) {
            return ""
        }
        return trimmed
    }

    private func validate(_ response: DanDanPlayBaseResponse) throws {
        guard response.success != false else {
            throw DanmakuAPIError.remote(response.errorMessage ?? "DanDanPlay API request failed")
        }
    }
}

// MARK: - Response Types

protocol DanDanPlayBaseResponse {
    var success: Bool? { get }
    var errorMessage: String? { get }
}

struct DanDanPlaySearchResponse: Decodable, DanDanPlayBaseResponse {
    let animes: [DanDanPlayBangumi]
    let errorCode: Int?
    let success: Bool?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case animes
        case errorCode
        case success
        case errorMessage
    }
}

struct DanDanPlayBangumiInfoResponse: Decodable, DanDanPlayBaseResponse {
    let bangumi: DanDanPlayBangumi?
    let errorCode: Int?
    let success: Bool?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case bangumi
        case errorCode
        case success
        case errorMessage
    }
}

struct DanDanPlayBangumi: Decodable, Identifiable {
    let animeId: Int
    let animeTitle: String
    let type: String?
    let typeDescription: String?
    let imageUrl: String?
    let episodeCount: Int?
    let rating: Double?
    let isFavorited: Bool?
    let episodes: [DanDanPlayEpisode]

    var id: Int { animeId }
    var name: String { animeTitle }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case animeId
        case animeTitle
        case type
        case typeDescription
        case imageUrl
        case episodeCount
        case rating
        case isFavorited
        case episodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        animeId = try container.decodeIfPresent(Int.self, forKey: .animeId)
            ?? container.decodeIfPresent(Int.self, forKey: .id)
            ?? 0
        animeTitle = try container.decodeIfPresent(String.self, forKey: .animeTitle)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type)
        typeDescription = try container.decodeIfPresent(String.self, forKey: .typeDescription)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        episodeCount = try container.decodeIfPresent(Int.self, forKey: .episodeCount)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        isFavorited = try container.decodeIfPresent(Bool.self, forKey: .isFavorited)
        episodes = try container.decodeIfPresent([DanDanPlayEpisode].self, forKey: .episodes) ?? []
    }
}

struct DanDanPlayEpisode: Decodable, Identifiable {
    let episodeId: Int
    let episodeTitle: String

    var id: Int { episodeId }
}

enum DanmakuAPIError: LocalizedError {
    case credentialsMissing
    case bangumiNotFound(Int)
    case invalidEpisodeID
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .credentialsMissing:
            return "未配置 DanDanPlay API 凭据"
        case .bangumiNotFound(let id):
            return "未找到 Bangumi 条目 \(id) 对应的弹幕库"
        case .invalidEpisodeID:
            return "弹幕分集 ID 无效"
        case .remote(let message):
            return message
        }
    }
}
