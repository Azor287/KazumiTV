//
//  Bangumi.swift
//  KazumiTV
//
//  Bangumi (Anime) Model
//

import Foundation

struct Bangumi: Identifiable, Codable, Equatable, Hashable {
    let id: Int
    let type: Int
    let name: String
    let nameCn: String
    let summary: String
    let airDate: String
    let airWeekday: Int
    let rank: Int
    let images: [String: String]
    let tags: [BangumiTag]
    let alias: [String]
    let ratingScore: Double
    let votes: Int
    let votesCount: [Int]
    let info: String

    enum CodingKeys: String, CodingKey {
        case id, type, name, nameCn, summary, airDate, airWeekday, rank, images, tags, alias, ratingScore, votes, votesCount, info
    }

    // MARK: - Hashable
    // Only hash by id for navigation purposes
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Bangumi, rhs: Bangumi) -> Bool {
        lhs.id == rhs.id
    }

    var displayName: String {
        nameCn.isEmpty ? name : nameCn
    }

    var largeImage: URL? {
        imageURL(for: ["large", "common", "grid", "medium", "small"])
    }

    var mediumImage: URL? {
        imageURL(for: ["medium", "common", "grid", "large", "small"])
    }

    var smallImage: URL? {
        imageURL(for: ["small", "grid", "common", "medium", "large"])
    }

    var gridImage: URL? {
        imageURL(for: ["grid", "common", "medium", "large", "small"])
    }

    private func imageURL(for keys: [String]) -> URL? {
        for key in keys {
            guard var urlString = images[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !urlString.isEmpty else {
                continue
            }

            if urlString.hasPrefix("//") {
                urlString = "https:" + urlString
            } else if urlString.hasPrefix("http://") {
                urlString = "https://" + urlString.dropFirst("http://".count)
            }

            if let url = URL(string: urlString) {
                return url
            }
        }

        return nil
    }

    var weekdayName: String {
        switch airWeekday {
        case 1: return "周一"
        case 2: return "周二"
        case 3: return "周三"
        case 4: return "周四"
        case 5: return "周五"
        case 6: return "周六"
        case 7: return "周日"
        default: return "未知"
        }
    }
}

// MARK: - BangumiTag
struct BangumiTag: Codable, Equatable, Hashable {
    let name: String
    let count: Int
}

struct BangumiSubjectComment: Identifiable, Equatable, Hashable {
    let id: Int
    let userName: String
    let content: String
    let createdAt: String

    init(json: [String: Any]) {
        id = json["id"] as? Int ?? 0
        content = json["content"] as? String
            ?? json["comment"] as? String
            ?? ""
        createdAt = json["created_at"] as? String
            ?? json["createdAt"] as? String
            ?? ""

        let user = json["user"] as? [String: Any]
            ?? json["creator"] as? [String: Any]
            ?? [:]
        userName = user["nickname"] as? String
            ?? user["username"] as? String
            ?? user["name"] as? String
            ?? "Bangumi 用户"
    }
}

struct BangumiCharacterCredit: Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let nameCn: String
    let relation: String
    let actorName: String
    let image: String

    init(json: [String: Any]) {
        let character = json["character"] as? [String: Any] ?? json
        id = character["id"] as? Int ?? json["id"] as? Int ?? 0
        name = character["name"] as? String ?? ""
        nameCn = character["name_cn"] as? String
            ?? character["nameCN"] as? String
            ?? ""
        relation = json["relation"] as? String
            ?? json["type"] as? String
            ?? ""

        let actors = json["actors"] as? [[String: Any]] ?? []
        let firstActor = actors.first ?? [:]
        actorName = firstActor["name"] as? String
            ?? firstActor["name_cn"] as? String
            ?? ""

        let images = character["images"] as? [String: Any] ?? [:]
        image = images["grid"] as? String
            ?? images["medium"] as? String
            ?? images["small"] as? String
            ?? ""
    }

    var displayName: String {
        nameCn.isEmpty ? name : nameCn
    }
}

struct BangumiStaffCredit: Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let nameCn: String
    let jobs: [String]
    let image: String

    init(json: [String: Any]) {
        let person = json["staff"] as? [String: Any]
            ?? json["person"] as? [String: Any]
            ?? json
        id = person["id"] as? Int ?? json["id"] as? Int ?? 0
        name = person["name"] as? String ?? ""
        nameCn = person["nameCN"] as? String
            ?? person["name_cn"] as? String
            ?? ""

        if let positions = json["positions"] as? [[String: Any]] {
            jobs = positions.compactMap { position in
                let type = position["type"] as? [String: Any] ?? [:]
                return type["cn"] as? String
                    ?? type["jp"] as? String
                    ?? type["en"] as? String
                    ?? position["summary"] as? String
            }.filter { !$0.isEmpty }
        } else if let career = json["career"] as? [String] {
            jobs = career
        } else if let positions = json["positions"] as? [String] {
            jobs = positions
        } else if let summary = json["summary"] as? String, !summary.isEmpty {
            jobs = [summary]
        } else {
            jobs = []
        }

        let images = person["images"] as? [String: Any] ?? [:]
        image = images["grid"] as? String
            ?? images["medium"] as? String
            ?? images["small"] as? String
            ?? ""
    }

    var displayName: String {
        let primaryName = name.isEmpty ? nameCn : name
        return primaryName.isEmpty ? "未知制作人员" : primaryName
    }
}

// MARK: - Sample Data
extension Bangumi {
    static let sample = Bangumi(
        id: 1,
        type: 2,
        name: "Test Anime",
        nameCn: "测试动画",
        summary: "This is a test anime description.",
        airDate: "2024-01-01",
        airWeekday: 1,
        rank: 1,
        images: [
            "large": "https://bgm.tv/img/no_icon_subject.png",
            "common": "https://bgm.tv/img/no_icon_subject.png"
        ],
        tags: [BangumiTag(name: "Test", count: 100)],
        alias: ["Test Anime"],
        ratingScore: 8.5,
        votes: 1000,
        votesCount: [10, 20, 30, 40, 50, 60, 70, 80, 90, 100],
        info: ""
    )

    static let samples: [Bangumi] = [
        Bangumi(
            id: 1,
            type: 2,
            name: "テストアニメ",
            nameCn: "测试动画",
            summary: "这是一个测试动画。",
            airDate: "2024-01-01",
            airWeekday: 1,
            rank: 1,
            images: ["large": "https://bgm.tv/img/no_icon_subject.png"],
            tags: [],
            alias: [],
            ratingScore: 8.5,
            votes: 1000,
            votesCount: [],
            info: ""
        ),
        Bangumi(
            id: 2,
            type: 2,
            name: "Another Anime",
            nameCn: "另一个动画",
            summary: "这是另一个测试动画。",
            airDate: "2024-04-01",
            airWeekday: 3,
            rank: 5,
            images: ["large": "https://bgm.tv/img/no_icon_subject.png"],
            tags: [],
            alias: [],
            ratingScore: 7.8,
            votes: 500,
            votesCount: [],
            info: ""
        )
    ]
}
