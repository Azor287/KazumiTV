//
//  Episode.swift
//  KazumiTV
//
//  Episode Model
//

import Foundation

struct Episode: Identifiable, Codable, Equatable, Hashable {
    let id: Int
    let bangumiId: Int
    let episodeNumber: Int
    let name: String
    let nameCn: String
    let airDate: String
    let duration: String
    let description: String
    let type: EpisodeType
    var pageURL: String?
    var pluginName: String?

    enum EpisodeType: Int, Codable, Hashable {
        case normal = 0
        case sp = 1
        case opening = 2
        case ending = 3
        case preview = 4
    }

    var displayName: String {
        if nameCn.isEmpty {
            return name.isEmpty ? "第\(episodeNumber)话" : name
        }
        return nameCn
    }
}

extension Episode {
    static let sample = Episode(
        id: 1,
        bangumiId: 1,
        episodeNumber: 1,
        name: "Episode 1",
        nameCn: "第一话",
        airDate: "2024-01-01",
        duration: "24:00",
        description: "First episode",
        type: .normal,
        pageURL: nil,
        pluginName: nil
    )
}
