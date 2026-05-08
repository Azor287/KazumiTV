//
//  PlaybackSession.swift
//  KazumiTV
//
//  Source-scoped playback context passed from detail to player.
//

import Foundation

struct PlaybackRoad: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let episodes: [Episode]
}

struct PlaybackSession: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let bangumi: Bangumi
    let source: SearchItem
    let candidateSources: [SearchItem]
    let roads: [PlaybackRoad]
    let selectedRoadID: String
    let selectedEpisodeID: Int
    let resumePosition: TimeInterval?
    let isUserSelected: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case bangumi
        case source
        case candidateSources
        case roads
        case selectedRoadID
        case selectedEpisodeID
        case resumePosition
        case isUserSelected
    }

    init(
        bangumi: Bangumi,
        source: SearchItem,
        candidateSources: [SearchItem] = [],
        roads: [PlaybackRoad],
        selectedRoadID: String,
        selectedEpisodeID: Int,
        resumePosition: TimeInterval? = nil,
        isUserSelected: Bool = false
    ) {
        self.id = "\(bangumi.id)-\(source.pluginName)-\(source.src)-\(selectedRoadID)-\(selectedEpisodeID)"
        self.bangumi = bangumi
        self.source = source
        self.candidateSources = candidateSources
        self.roads = roads
        self.selectedRoadID = selectedRoadID
        self.selectedEpisodeID = selectedEpisodeID
        self.resumePosition = resumePosition
        self.isUserSelected = isUserSelected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bangumi = try container.decode(Bangumi.self, forKey: .bangumi)
        source = try container.decode(SearchItem.self, forKey: .source)
        candidateSources = try container.decodeIfPresent([SearchItem].self, forKey: .candidateSources) ?? []
        roads = try container.decode([PlaybackRoad].self, forKey: .roads)
        selectedRoadID = try container.decode(String.self, forKey: .selectedRoadID)
        selectedEpisodeID = try container.decode(Int.self, forKey: .selectedEpisodeID)
        resumePosition = try container.decodeIfPresent(TimeInterval.self, forKey: .resumePosition)
        isUserSelected = try container.decodeIfPresent(Bool.self, forKey: .isUserSelected) ?? false
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? "\(bangumi.id)-\(source.pluginName)-\(source.src)-\(selectedRoadID)-\(selectedEpisodeID)"
    }

    var selectedRoad: PlaybackRoad? {
        roads.first(where: { $0.id == selectedRoadID }) ?? roads.first
    }

    var selectedEpisode: Episode? {
        selectedRoad?.episodes.first(where: { $0.id == selectedEpisodeID }) ?? selectedRoad?.episodes.first
    }
}
