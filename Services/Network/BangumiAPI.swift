//
//  BangumiAPI.swift
//  KazumiTV
//
//  Bangumi.tv API
//

import Foundation

actor BangumiAPI {
    static let shared = BangumiAPI()

    private let api = APIClient.shared
    private let decoder = JSONDecoder()

    // API Endpoints
    private let bangumiAPIDomain = "https://api.bgm.tv"
    private let bangumiAPINextDomain = "https://next.bgm.tv"

    private init() {
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Calendar (Weekly Schedule)

    /// Get weekly calendar from Bangumi (next.bgm.tv)
    func getCalendar() async throws -> [[Bangumi]] {
        do {
            let calendar = try await getNextCalendar()
            if calendar.contains(where: { !$0.isEmpty }) {
                return calendar
            }
        } catch {
            print("BangumiAPI.getCalendar: next calendar failed, falling back to legacy calendar: \(error)")
        }

        return try await getLegacyCalendar()
    }

    private func getNextCalendar() async throws -> [[Bangumi]] {
        let url = URL(string: "\(bangumiAPINextDomain)/p1/calendar")!
        let (data, _) = try await api.get(url: url, headers: HTTPHeaders.bangumiHeaders())

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        var calendar: [[Bangumi]] = Array(repeating: [], count: 7)

        // New API format: {"1": [...], "2": [...], ...}
        for dayIndex in 1...7 {
            var dayBangumis: [Bangumi] = []

            if let dayItems = json["\(dayIndex)"] as? [[String: Any]] {
                for item in dayItems {
                    if let subject = item["subject"] as? [String: Any],
                       let bangumi = try? parseBangumi(from: subject) {
                        dayBangumis.append(bangumi)
                    }
                }
            }
            calendar[dayIndex - 1] = dayBangumis
        }

        return calendar
    }

    private func getLegacyCalendar() async throws -> [[Bangumi]] {
        let url = URL(string: "\(bangumiAPIDomain)/calendar")!
        let data = try await getBangumiAPI(url: url)

        guard let days = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw APIError.invalidResponse
        }

        var calendar: [[Bangumi]] = Array(repeating: [], count: 7)

        for day in days {
            let weekday = day["weekday"] as? [String: Any] ?? [:]
            let weekdayID = (weekday["id"] as? Int)
                ?? Int("\(weekday["id"] ?? 0)")
                ?? 0
            guard weekdayID >= 1 && weekdayID <= 7 else { continue }

            let items = day["items"] as? [[String: Any]] ?? []
            calendar[weekdayID - 1] = items.compactMap { try? parseBangumi(from: $0) }
        }

        return calendar
    }

    // MARK: - Search

    /// Search bangumi by keyword
    func search(keyword: String, limit: Int = 20, offset: Int = 0) async throws -> [Bangumi] {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        let urlString = "\(bangumiAPIDomain)/v0/search/subjects?limit=\(limit)&offset=\(offset)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }

        let body: [String: Any] = [
            "keyword": keyword,
            "sort": "rank",
            "filter": [
                "type": [2],
                "nsfw": false
            ] as [String : Any]
        ]

        let data = try await postBangumiAPI(url: url, body: body)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        let items = json["data"] as? [[String: Any]] ?? []
        return items.compactMap { try? parseBangumi(from: $0) }
    }

    // MARK: - Bangumi Info

    /// Get bangumi details by ID
    func getBangumiInfo(id: Int) async throws -> Bangumi {
        let urlString = "\(bangumiAPIDomain)/v0/subjects/\(id)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }

        let data = try await getBangumiAPI(url: url)
        return try parseBangumi(from: data)
    }

    // MARK: - Episodes

    /// Get episodes for a bangumi
    func getEpisodes(subjectId: Int, limit: Int = 100, offset: Int = 0) async throws -> [Episode] {
        var components = URLComponents(string: "\(bangumiAPIDomain)/v0/episodes")!
        components.queryItems = [
            URLQueryItem(name: "subject_id", value: "\(subjectId)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]

        guard let url = components.url else {
            throw APIError.invalidResponse
        }

        let data = try await getBangumiAPI(url: url)

        let response = try decoder.decode(EpisodesResponse.self, from: data)
        return response.data.map { Episode(from: $0) }
    }

    // MARK: - Detail Aux Info

    func getSubjectComments(id: Int, limit: Int = 20, offset: Int = 0) async throws -> [BangumiSubjectComment] {
        let urlString = "\(bangumiAPINextDomain)/p1/subjects/\(id)/comments?limit=\(limit)&offset=\(offset)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }

        let (data, _) = try await api.get(url: url, headers: HTTPHeaders.bangumiHeaders())
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        let items = json["data"] as? [[String: Any]] ?? []
        return items.map { BangumiSubjectComment(json: $0) }
    }

    func getSubjectCharacters(id: Int) async throws -> [BangumiCharacterCredit] {
        let urlString = "\(bangumiAPIDomain)/v0/subjects/\(id)/characters"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }

        let data = try await getBangumiAPI(url: url)
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw APIError.invalidResponse
        }

        return items.map { BangumiCharacterCredit(json: $0) }
    }

    func getSubjectStaff(id: Int) async throws -> [BangumiStaffCredit] {
        let urlString = "\(bangumiAPINextDomain)/p1/subjects/\(id)/staffs/persons"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }

        let (data, _) = try await api.get(url: url, headers: HTTPHeaders.bangumiHeaders())
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw APIError.invalidResponse
        }

        let items: [[String: Any]]
        if let array = json as? [[String: Any]] {
            items = array
        } else if let object = json as? [String: Any] {
            items = object["data"] as? [[String: Any]] ?? []
        } else {
            items = []
        }

        return items.map { BangumiStaffCredit(json: $0) }
    }

    // MARK: - Trends

    /// Get trending/popular bangumis
    func getTrends(limit: Int = 24, offset: Int = 0) async throws -> [Bangumi] {
        do {
            let result = try await getNextTrends(limit: limit, offset: offset)
            if !result.isEmpty {
                return result
            }
            print("BangumiAPI.getTrends: next trending returned empty, falling back to v0 search")
        } catch {
            print("BangumiAPI.getTrends: next trending failed, falling back to v0 search: \(error)")
        }

        do {
            return try await getRankedBangumis(limit: limit, offset: offset, sort: "heat")
        } catch {
            print("BangumiAPI.getTrends: v0 heat search failed, falling back to rank search: \(error)")
            return try await getRankedBangumis(limit: limit, offset: offset, sort: "rank")
        }
    }

    /// Get popular bangumis using the stable v0 search API.
    func getPopularBangumis(limit: Int = 24, offset: Int = 0) async throws -> [Bangumi] {
        try await getRankedBangumis(limit: limit, offset: offset)
    }

    /// Get popular bangumis filtered by a Bangumi tag.
    func getTaggedBangumis(tag: String, limit: Int = 24, offset: Int = 0) async throws -> [Bangumi] {
        try await getRankedBangumis(limit: limit, offset: offset, tags: [tag])
    }

    private func getNextTrends(limit: Int, offset: Int) async throws -> [Bangumi] {
        var components = URLComponents(string: "\(bangumiAPINextDomain)/p1/trending/subjects")!
        components.queryItems = [
            URLQueryItem(name: "type", value: "2"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]

        guard let url = components.url else {
            throw APIError.invalidResponse
        }

        let (data, _) = try await api.get(url: url, headers: HTTPHeaders.bangumiHeaders())

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        let items = json["data"] as? [[String: Any]] ?? []

        var result: [Bangumi] = []
        for item in items {
            let subject = item["subject"] as? [String: Any] ?? item
            if let bangumi = try? parseBangumi(from: subject) {
                result.append(bangumi)
            }
        }
        return result
    }

    private func getRankedBangumis(
        limit: Int,
        offset: Int,
        tags: [String] = [],
        sort: String = "heat"
    ) async throws -> [Bangumi] {
        let cappedLimit = min(max(limit, 1), 20)
        let urlString = "\(bangumiAPIDomain)/v0/search/subjects?limit=\(cappedLimit)&offset=\(offset)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }

        var filter: [String: Any] = [
            "type": [2],
            "rank": sort == "rank" ? [">0", "<=99999"] : [">=0", "<=99999"],
            "nsfw": false
        ]
        if !tags.isEmpty {
            filter["tag"] = tags
        }

        let body: [String: Any] = [
            "keyword": "",
            "sort": sort,
            "filter": filter
        ]

        let data = try await postBangumiAPI(url: url, body: body)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        let items = json["data"] as? [[String: Any]] ?? []
        return items.compactMap { try? parseBangumi(from: $0) }
    }

    // MARK: - Helper Methods

    private func parseBangumi(from data: Data) throws -> Bangumi {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return try parseBangumi(from: json)
    }

    private func getBangumiAPI(url: URL) async throws -> Data {
        do {
            let (data, _) = try await api.get(url: url, headers: HTTPHeaders.bangumiHeaders())
            return data
        } catch {
            guard shouldRetryBangumiRequestOverHTTP(error),
                  let fallbackURL = httpFallbackURL(for: url) else {
                throw error
            }

            let (data, _) = try await api.get(url: fallbackURL, headers: HTTPHeaders.bangumiHeaders())
            return data
        }
    }

    private func postBangumiAPI(url: URL, body: [String: Any]) async throws -> Data {
        do {
            let (data, _) = try await api.post(url: url, body: body, headers: HTTPHeaders.bangumiHeaders())
            return data
        } catch {
            guard shouldRetryBangumiRequestOverHTTP(error),
                  let fallbackURL = httpFallbackURL(for: url) else {
                throw error
            }

            let (data, _) = try await api.post(url: fallbackURL, body: body, headers: HTTPHeaders.bangumiHeaders())
            return data
        }
    }

    private func httpFallbackURL(for url: URL) -> URL? {
        guard url.scheme == "https", url.host == "api.bgm.tv" else {
            return nil
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "http"
        components?.host = "api.bgm.tv"
        return components?.url
    }

    private func shouldRetryBangumiRequestOverHTTP(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }

        return [
            NSURLErrorSecureConnectionFailed,
            NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasUnknownRoot,
            NSURLErrorServerCertificateNotYetValid,
            NSURLErrorClientCertificateRejected,
            NSURLErrorClientCertificateRequired
        ].contains(nsError.code)
    }

    private func parseBangumi(from json: [String: Any]) throws -> Bangumi {
        let imagesDict = parseImages(from: json)

        let rating = json["rating"] as? [String: Any] ?? [:]
        let ratingScore = Double("\(rating["score"] ?? 0)")

        let votes = (rating["total"] as? Int)
            ?? Int("\(rating["total"] ?? 0)")
            ?? (json["votes"] as? Int)
            ?? 0
        let votesCount = parseRatingCount(from: rating)

        let dateStr = json["date"] as? String
            ?? json["air_date"] as? String
            ?? ""
        let airWeekday = (json["air_weekday"] as? Int)
            ?? Int("\(json["air_weekday"] ?? 0)")
            ?? dateStringToWeekday(dateStr)

        let nameCn = json["name_cn"] as? String
            ?? json["nameCN"] as? String
            ?? ""
        let aliases = parseAliases(from: json)
        let tags = parseTags(from: json)

        let rank = (json["rank"] as? Int)
            ?? Int("\(json["rank"] ?? 0)")
            ?? (rating["rank"] as? Int)
            ?? Int("\(rating["rank"] ?? 0)")
            ?? 0

        return Bangumi(
            id: json["id"] as? Int ?? 0,
            type: json["type"] as? Int ?? 2,
            name: json["name"] as? String ?? "",
            nameCn: nameCn,
            summary: json["summary"] as? String ?? "",
            airDate: dateStr,
            airWeekday: airWeekday,
            rank: rank,
            images: imagesDict,
            tags: tags,
            alias: aliases,
            ratingScore: ratingScore ?? 0,
            votes: votes,
            votesCount: votesCount,
            info: json["info"] as? String ?? ""
        )
    }

    private func parseImages(from json: [String: Any]) -> [String: String] {
        if let rawImages = json["images"] as? [String: Any] {
            return rawImages.reduce(into: [String: String]()) { result, item in
                if let value = item.value as? String {
                    result[item.key] = value
                } else {
                    result[item.key] = ""
                }
            }
        }

        if let image = json["image"] as? String, !image.isEmpty {
            return [
                "large": image,
                "common": image,
                "medium": image,
                "small": image,
                "grid": image
            ]
        }

        return [:]
    }

    private func parseTags(from json: [String: Any]) -> [BangumiTag] {
        guard let rawTags = json["tags"] as? [[String: Any]] else {
            return []
        }

        return rawTags.compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty else {
                return nil
            }

            let count = item["count"] as? Int
                ?? Int("\(item["count"] ?? 0)")
                ?? 0
            return BangumiTag(name: name, count: count)
        }
    }

    private func parseRatingCount(from rating: [String: Any]) -> [Int] {
        if let count = rating["count"] as? [String: Int] {
            return (1...10).map { count["\($0)"] ?? 0 }
        }

        if let count = rating["count"] as? [String: Any] {
            return (1...10).map { Int("\(count["\($0)"] ?? 0)") ?? 0 }
        }

        if let count = rating["count"] as? [Int] {
            if count.count >= 10 {
                return Array(count.prefix(10))
            }

            return count + Array(repeating: 0, count: 10 - count.count)
        }

        return []
    }

    private func dateStringToWeekday(_ dateString: String) -> Int {
        guard !dateString.isEmpty else { return 0 }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")

        guard let date = formatter.date(from: dateString) else { return 0 }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    private func parseAliases(from json: [String: Any]) -> [String] {
        if let aliases = json["alias"] as? [String] {
            return aliases
        }

        guard let infobox = json["infobox"] as? [[String: Any]] else {
            return []
        }

        var aliases: [String] = []
        for item in infobox {
            let key = item["key"] as? String ?? ""
            guard key == "别名" || key.lowercased() == "alias" else { continue }

            if let values = item["value"] as? [[String: Any]] {
                for value in values {
                    if let alias = value["v"] as? String, !alias.isEmpty {
                        aliases.append(alias)
                    }
                }
            } else if let alias = item["value"] as? String, !alias.isEmpty {
                aliases.append(alias)
            }
        }

        return aliases
    }
}

// MARK: - Response Types

struct BangumiSearchResponse: Codable {
    let data: [Bangumi]
    let total: Int?
}

struct EpisodesResponse: Codable {
    let data: [EpisodeJSON]
}

struct EpisodeJSON: Codable {
    let id: Int
    let type: Int
    let sort: Double
    let name: String
    let nameCn: String
    let duration: String?
    let airDate: String?

    enum CodingKeys: String, CodingKey {
        case id, type, sort, name, nameCn, duration
        case airDate = "air_date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = try container.decode(Int.self, forKey: .type)
        sort = try container.decodeFlexibleDouble(forKey: .sort) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        nameCn = try container.decodeIfPresent(String.self, forKey: .nameCn) ?? ""
        duration = try container.decodeIfPresent(String.self, forKey: .duration)
        airDate = try container.decodeIfPresent(String.self, forKey: .airDate)
    }
}

extension Episode {
    init(from json: EpisodeJSON) {
        self.id = json.id
        self.bangumiId = 0
        self.episodeNumber = Int(json.sort.rounded(.down))
        self.name = json.name
        self.nameCn = json.nameCn
        self.airDate = json.airDate ?? ""
        self.duration = json.duration ?? ""
        self.description = ""
        self.type = EpisodeType(rawValue: json.type) ?? .normal
        self.pageURL = nil
        self.pluginName = nil
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDouble(forKey key: Key) throws -> Double? {
        if let value = try decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}
