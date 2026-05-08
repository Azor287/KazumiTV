//
//  FavoriteRepository.swift
//  KazumiTV
//
//  Favorites/Collections Repository
//

import Foundation

actor FavoriteRepository {
    static let shared = FavoriteRepository()

    private let db = DatabaseManager.shared

    // Collection types
    enum CollectionType: Int {
        case watching = 1   // 在看
        case wantToWatch = 2 // 想看
        case onHold = 3     // 搁置
        case watched = 4    // 看过
        case dropped = 5     // 抛弃
    }

    private init() {}

    // MARK: - CRUD Operations

    func addToCollection(bangumi: Bangumi, type: CollectionType) async throws {
        let existing = try await db.getCollectible(bangumiId: bangumi.id)
        let collected = CollectedBangumi(
            id: existing?.id ?? UUID().uuidString,
            bangumiId: bangumi.id,
            name: bangumi.name,
            nameCn: bangumi.nameCn,
            imageURL: bangumi.images["large"] ?? bangumi.images["common"] ?? bangumi.images["grid"] ?? bangumi.images["medium"] ?? "",
            eps: 0,
            airedEps: 0,
            addedAt: existing?.addedAt ?? Date(),
            lastWatchedAt: existing?.lastWatchedAt,
            lastWatchedEpisode: existing?.lastWatchedEpisode,
            watchProgress: existing?.watchProgress ?? [:],
            type: type.rawValue
        )
        try await db.insertCollectible(collected)
    }

    func getCollections() async throws -> [CollectedBangumi] {
        return try await db.getCollectibles()
    }

    func getCollections(type: CollectionType) async throws -> [CollectedBangumi] {
        let all = try await db.getCollectibles()
        return all.filter { $0.type == type.rawValue }
    }

    func isCollected(bangumiId: Int) async throws -> Bool {
        let collected = try await db.getCollectible(bangumiId: bangumiId)
        return collected != nil
    }

    func getCollection(bangumiId: Int) async throws -> CollectedBangumi? {
        return try await db.getCollectible(bangumiId: bangumiId)
    }

    func updateCollection(_ collected: CollectedBangumi) async throws {
        try await db.insertCollectible(collected)
    }

    func removeFromCollection(id: String) async throws {
        try await db.deleteCollectible(id: id)
    }

    func removeFromCollection(bangumiId: Int) async throws {
        if let collected = try await db.getCollectible(bangumiId: bangumiId) {
            try await db.deleteCollectible(id: collected.id)
        }
    }

    func updateWatchProgress(bangumiId: Int, episode: Int, progress: Double) async throws {
        guard var collected = try await db.getCollectible(bangumiId: bangumiId) else { return }
        collected.updateProgress(episode: episode, progress: progress)
        try await db.insertCollectible(collected)
    }
}

// MARK: - Convenience Extensions
extension FavoriteRepository {
    func getWatching() async throws -> [CollectedBangumi] {
        return try await getCollections(type: .watching)
    }

    func getWantToWatch() async throws -> [CollectedBangumi] {
        return try await getCollections(type: .wantToWatch)
    }

    func getOnHold() async throws -> [CollectedBangumi] {
        return try await getCollections(type: .onHold)
    }

    func getWatched() async throws -> [CollectedBangumi] {
        return try await getCollections(type: .watched)
    }

    func getDropped() async throws -> [CollectedBangumi] {
        return try await getCollections(type: .dropped)
    }
}
