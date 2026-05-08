//
//  DanDanPlayAPI.swift
//  KazumiTV
//
//  DanDanPlay Danmaku API
//

import Foundation

actor DanDanPlayAPI {
    static let shared = DanDanPlayAPI()

    private let api = APIClient.shared
    private let decoder = JSONDecoder()

    // API Endpoints
    private let dandanAPIDomain = "https://api.dandanplay.net"

    private init() {
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Search

    /// Search for bangumi by name on DanDanPlay
    func searchBangumi(keyword: String) async throws -> [DanDanPlayBangumi] {
        let urlString = "\(dandanAPIDomain)/api/v2/search/anime"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }

        let body: [String: Any] = [
            "searchQuery": keyword,
            "isExact": false
        ]

        let (data, _) = try await api.post(url: url, body: body)
        let response = try decoder.decode(DanDanPlaySearchResponse.self, from: data)
        return response.animes
    }

    // MARK: - Get Comments (Danmaku)

    /// Get danmaku comments for a bangumi episode
    /// - Parameters:
    ///   - bangumiId: DanDanPlay bangumi ID
    ///   - episode: Episode number (e.g., 1 for first episode)
    func getComments(bangumiId: Int, episode: Int) async throws -> [DanmakuItem] {
        let urlString = "\(dandanAPIDomain)/api/v2/comment/\(bangumiId),\(episode)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }

        let (data, _) = try await api.get(url: url)

        let response = try decoder.decode(DanDanPlayResponse.self, from: data)
        return response.comments.map { DanmakuItem(from: $0) }
    }

    /// Get danmaku by Bangumi.tv ID
    func getCommentsByBgmId(bgmBangumiId: Int, episode: Int) async throws -> [DanmakuItem] {
        let urlString = "\(dandanAPIDomain)/api/v2/comment/bgmtv,\(bgmBangumiId),\(episode)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }

        let (data, _) = try await api.get(url: url)

        let response = try decoder.decode(DanDanPlayResponse.self, from: data)
        return response.comments.map { DanmakuItem(from: $0) }
    }

    // MARK: - Get Bangumi Info

    /// Get DanDanPlay bangumi info by ID
    func getBangumiInfo(bangumiId: Int) async throws -> DanDanPlayBangumi? {
        let urlString = "\(dandanAPIDomain)/api/v2/bangumi/\(bangumiId)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }

        let (data, _) = try await api.get(url: url)

        let response = try decoder.decode(DanDanPlayBangumi.self, from: data)
        return response
    }

    /// Get DanDanPlay bangumi info by Bangumi.tv ID
    func getBangumiInfoByBgmId(bgmBangumiId: Int) async throws -> DanDanPlayBangumi? {
        let urlString = "\(dandanAPIDomain)/api/v2/bangumi/bgmtv/\(bgmBangumiId)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }

        let (data, _) = try await api.get(url: url)

        let response = try decoder.decode(DanDanPlayBangumi.self, from: data)
        return response
    }
}

// MARK: - Response Types

struct DanDanPlaySearchResponse: Codable {
    let animes: [DanDanPlayBangumi]
    let resultCode: Int

    enum CodingKeys: String, CodingKey {
        case animes
        case resultCode = "resultCode"
    }
}

struct DanDanPlayBangumi: Codable {
    let id: Int
    let name: String
    let type: Int
    let episodes: [Int]
    let images: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, name, type, episodes, images
    }
}
