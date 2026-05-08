//
//  HistoryViewModel.swift
//  KazumiTV
//
//  Watch History ViewModel
//

import Foundation
import Combine

@MainActor
class HistoryViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var histories: [History] = []
    @Published var isLoading = false
    @Published var isPreparingPlayback = false
    @Published var error: Error?

    // MARK: - Services
    private let historyRepository = HistoryRepository.shared
    private var hasLoadedData = false

    // MARK: - Init

    init() {}

    // MARK: - Load Data

    func loadData() async {
        isLoading = true
        error = nil

        do {
            histories = try await historyRepository.getHistories(limit: 100)
            hasLoadedData = true
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func loadDataIfNeeded() async {
        guard !hasLoadedData, !isLoading else { return }
        await loadData()
    }

    // MARK: - Add

    func addHistory(
        bangumiId: Int,
        episodeId: Int,
        episodeNumber: Int,
        episodeName: String,
        bangumiName: String,
        bangumiImage: String,
        progress: TimeInterval,
        duration: TimeInterval,
        source: String,
        sourceURL: String = "",
        sourceName: String = ""
    ) async {
        do {
            try await historyRepository.addHistory(
                bangumiId: bangumiId,
                episodeId: episodeId,
                episodeNumber: episodeNumber,
                episodeName: episodeName,
                bangumiName: bangumiName,
                bangumiImage: bangumiImage,
                progress: progress,
                duration: duration,
                source: source,
                sourceURL: sourceURL,
                sourceName: sourceName
            )
            await loadData()
        } catch {
            self.error = error
        }
    }

    // MARK: - Delete

    func deleteHistory(id: String) async {
        do {
            try await historyRepository.deleteHistory(id: id)
            histories.removeAll { $0.id == id }
        } catch {
            self.error = error
        }
    }

    func clearAllHistory() async {
        do {
            try await historyRepository.clearAllHistory()
            histories = []
        } catch {
            self.error = error
        }
    }

    // MARK: - Refresh

    func refresh() async {
        await loadData()
    }

    // MARK: - Playback

    func makePlaybackSession(for history: History) async throws -> PlaybackSession {
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }

        guard let sourceItem = history.searchItem else {
            throw HistoryPlaybackError.missingSource
        }

        let pluginManager = PluginManager.shared
        try await pluginManager.loadPlugins()

        guard let plugin = await pluginManager.getPlugin(name: sourceItem.pluginName) else {
            throw HistoryPlaybackError.pluginNotFound(sourceItem.pluginName)
        }

        let chapterRoads = try await pluginManager.getChapters(pageURL: sourceItem.src, plugin: plugin)
        let roads = chapterRoads
            .filter { !$0.episodes.isEmpty }
            .map { road in
                PlaybackRoad(
                    id: road.id,
                    name: road.name,
                    episodes: playbackEpisodes(from: road, history: history, pluginName: sourceItem.pluginName)
                )
            }
            .filter { !$0.episodes.isEmpty }

        guard let selectedRoad = roads.first(where: { road in
            road.episodes.contains { $0.episodeNumber == history.episodeNumber }
        }) ?? roads.first else {
            throw HistoryPlaybackError.noEpisodes
        }

        let selectedEpisode = selectedRoad.episodes.first { $0.episodeNumber == history.episodeNumber }
            ?? selectedRoad.episodes.first

        guard let selectedEpisode else {
            throw HistoryPlaybackError.noEpisodes
        }

        return PlaybackSession(
            bangumi: history.bangumi,
            source: sourceItem,
            candidateSources: [],
            roads: roads,
            selectedRoadID: selectedRoad.id,
            selectedEpisodeID: selectedEpisode.id,
            resumePosition: resumePosition(from: history)
        )
    }

    private func resumePosition(from history: History) -> TimeInterval? {
        guard history.progress > 1 else { return nil }

        if history.duration > 0 {
            return min(history.progress, history.duration)
        }

        return history.progress
    }

    private func playbackEpisodes(from road: ChapterRoad, history: History, pluginName: String) -> [Episode] {
        road.episodes.enumerated().map { index, item in
            let episodeName = item.episode == history.episodeNumber && !history.episodeName.isEmpty
                ? history.episodeName
                : item.name

            return Episode(
                id: -((index + 1) * 10_000 + stableEpisodeSuffix(from: "\(pluginName)-\(road.id)-\(item.src)")),
                bangumiId: history.bangumiId,
                episodeNumber: item.episode,
                name: episodeName.isEmpty ? "第 \(item.episode) 集" : episodeName,
                nameCn: "",
                airDate: "",
                duration: "",
                description: "",
                type: .normal,
                pageURL: item.src,
                pluginName: pluginName
            )
        }
    }

    private func stableEpisodeSuffix(from value: String) -> Int {
        value.unicodeScalars.reduce(0) { partialResult, scalar in
            (partialResult &* 31 &+ Int(scalar.value)) % 9_999
        }
    }
}

private enum HistoryPlaybackError: LocalizedError {
    case missingSource
    case pluginNotFound(String)
    case noEpisodes

    var errorDescription: String? {
        switch self {
        case .missingSource:
            return "这条历史缺少播放源信息"
        case .pluginNotFound(let name):
            return "未找到关联播放源：\(name)"
        case .noEpisodes:
            return "没有解析到可播放章节"
        }
    }
}
