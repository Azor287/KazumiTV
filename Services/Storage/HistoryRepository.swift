//
//  HistoryRepository.swift
//  KazumiTV
//
//  Watch History Repository
//

import Foundation

actor HistoryRepository {
    static let shared = HistoryRepository()

    private let db = DatabaseManager.shared

    private init() {}

    // MARK: - CRUD Operations

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
    ) async throws {
        guard !SettingsRepository.shared.privateMode else { return }
        guard progress > 0 else { return }

        let history = History(
            id: historyID(bangumiId: bangumiId),
            bangumiId: bangumiId,
            episodeId: episodeId,
            episodeNumber: episodeNumber,
            episodeName: episodeName,
            bangumiName: bangumiName,
            bangumiImage: bangumiImage,
            progress: progress,
            duration: duration,
            lastWatchedAt: Date(),
            source: source,
            sourceURL: sourceURL,
            sourceName: sourceName
        )
        try await db.insertHistory(history)
        try await syncTopShelf()
        await notifyHistoryDidChange()
    }

    func getHistories(limit: Int = 100) async throws -> [History] {
        return try await db.getHistories(limit: limit)
    }

    func deleteHistory(id: String) async throws {
        try await db.deleteHistory(id: id)
        try await syncTopShelf()
        await notifyHistoryDidChange()
    }

    func clearAllHistory() async throws {
        try await db.clearHistories()
        try await syncTopShelf()
        await notifyHistoryDidChange()
    }

    // MARK: - Query Operations

    func getHistoryForEpisode(bangumiId: Int, episodeNumber: Int) async throws -> History? {
        let all = try await db.getHistories(limit: 1000)
        return all.first { $0.bangumiId == bangumiId && $0.episodeNumber == episodeNumber }
    }

    func getLatestHistory() async throws -> History? {
        let all = try await db.getHistories(limit: 1)
        return all.first
    }

    func getHistoriesForBangumi(bangumiId: Int) async throws -> [History] {
        let all = try await db.getHistories(limit: 1000)
        return all.filter { $0.bangumiId == bangumiId }
    }

    private func historyID(bangumiId: Int) -> String {
        "history|\(bangumiId)"
    }

    private func syncTopShelf() async throws {
        await TopShelfSyncService.syncHistory(try await db.getHistories(limit: 20))
    }

    private func notifyHistoryDidChange() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let watchHistoryDidChange = Notification.Name("watchHistoryDidChange")
}
