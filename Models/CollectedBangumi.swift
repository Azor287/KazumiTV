//
//  CollectedBangumi.swift
//  KazumiTV
//
//  Collected/Favorited Bangumi Model
//

import Foundation

struct CollectedBangumi: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let bangumiId: Int
    let name: String
    let nameCn: String
    let imageURL: String
    let eps: Int
    let airedEps: Int
    let addedAt: Date
    var lastWatchedAt: Date?
    var lastWatchedEpisode: Int?
    var watchProgress: [Int: Double]
    var type: Int  // 1=在看, 2=想看, 3=搁置, 4=看过, 5=抛弃

    init(
        id: String = UUID().uuidString,
        bangumiId: Int,
        name: String,
        nameCn: String,
        imageURL: String,
        eps: Int,
        airedEps: Int,
        addedAt: Date = Date(),
        lastWatchedAt: Date? = nil,
        lastWatchedEpisode: Int? = nil,
        watchProgress: [Int: Double] = [:],
        type: Int = 1
    ) {
        self.id = id
        self.bangumiId = bangumiId
        self.name = name
        self.nameCn = nameCn
        self.imageURL = imageURL
        self.eps = eps
        self.airedEps = airedEps
        self.addedAt = addedAt
        self.lastWatchedAt = lastWatchedAt
        self.lastWatchedEpisode = lastWatchedEpisode
        self.watchProgress = watchProgress
        self.type = type
    }

    var displayName: String {
        nameCn.isEmpty ? name : nameCn
    }

    // MARK: - Hashable
    // Only hash by id for navigation purposes
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CollectedBangumi, rhs: CollectedBangumi) -> Bool {
        lhs.id == rhs.id
    }

    var progressPercentage: Double {
        guard airedEps > 0 else { return 0 }
        let watchedEps = watchProgress.count
        return Double(watchedEps) / Double(airedEps)
    }

    var statusText: String {
        if let lastWatchedEpisode {
            return "看到第\(lastWatchedEpisode)话"
        }

        if eps == 0 && airedEps == 0 {
            return "已追番"
        }

        if airedEps == 0 {
            return "未播出"
        } else if airedEps >= eps {
            return "已看完"
        } else {
            return "未开始观看"
        }
    }

    var collectionTypeText: String {
        switch type {
        case 1: return "在看"
        case 2: return "想看"
        case 3: return "搁置"
        case 4: return "看过"
        case 5: return "抛弃"
        default: return "未追"
        }
    }

    mutating func updateProgress(episode: Int, progress: Double) {
        watchProgress[episode] = progress
        lastWatchedAt = Date()
        lastWatchedEpisode = episode
    }
}

extension CollectedBangumi {
    static let sample = CollectedBangumi(
        bangumiId: 1,
        name: "テストアニメ",
        nameCn: "测试动画",
        imageURL: "https://bgm.tv/img/no_icon_subject.png",
        eps: 12,
        airedEps: 6,
        lastWatchedAt: Date(),
        lastWatchedEpisode: 5,
        watchProgress: [1: 1.0, 2: 1.0, 3: 1.0, 4: 1.0, 5: 0.6]
    )
}
