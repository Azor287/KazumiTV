import Foundation

enum TopShelfSyncService {
    static func syncAll() async {
        do {
            let collections = try await FavoriteRepository.shared.getCollections()
            await syncFavorites(collections)
        } catch {
            print("TopShelfSyncService: failed to sync favorites: \(error.localizedDescription)")
        }

        do {
            let histories = try await HistoryRepository.shared.getHistories(limit: 20)
            await syncHistory(histories)
        } catch {
            print("TopShelfSyncService: failed to sync history: \(error.localizedDescription)")
        }
    }

    static func syncFavorites(_ collections: [CollectedBangumi]) async {
        let candidates = Array(collections
            .filter { $0.type != FavoriteRepository.CollectionType.dropped.rawValue }
            .sorted {
                ($0.lastWatchedAt ?? $0.addedAt) > ($1.lastWatchedAt ?? $1.addedAt)
            }
            .prefix(20))
        let allowedSubjectIDs = await allowedSubjectIDs(
            candidates.map(\.bangumiId)
        )
        let items = candidates
            .filter { allowedSubjectIDs.contains($0.bangumiId) }
            .map { item in
                TopShelfSharedItem(
                    identifier: "favorite-\(item.bangumiId)",
                    subjectID: item.bangumiId,
                    title: item.displayName,
                    contextTitle: "用户追番 · \(item.collectionTypeText)",
                    summary: item.statusText,
                    imageURL: normalizedImageURL(item.imageURL),
                    updatedAt: item.lastWatchedAt ?? item.addedAt
                )
            }
        TopShelfSharedStore.save(Array(items), for: .favorites)
    }

    static func syncHistory(_ histories: [History]) async {
        let candidates = Array(histories
            .sorted { $0.lastWatchedAt > $1.lastWatchedAt }
            .prefix(20))
        let allowedSubjectIDs = await allowedSubjectIDs(
            candidates.map(\.bangumiId)
        )
        let items = candidates
            .filter { allowedSubjectIDs.contains($0.bangumiId) }
            .map { item in
                TopShelfSharedItem(
                    identifier: "history-\(item.bangumiId)",
                    subjectID: item.bangumiId,
                    title: item.bangumiName,
                    contextTitle: "播放历史 · 第 \(item.episodeNumber) 话",
                    summary: "\(item.displayEpisodeName) · \(item.playbackProgressText)",
                    imageURL: normalizedImageURL(item.bangumiImage),
                    updatedAt: item.lastWatchedAt
                )
            }
        TopShelfSharedStore.save(Array(items), for: .history)
    }

    private static func normalizedImageURL(_ rawValue: String) -> String {
        if rawValue.hasPrefix("//") {
            return "https:" + rawValue
        }
        if rawValue.hasPrefix("http://") {
            return "https://" + rawValue.dropFirst("http://".count)
        }
        return rawValue
    }

    private static func allowedSubjectIDs(_ subjectIDs: [Int]) async -> Set<Int> {
        await withTaskGroup(of: (Int, Bool).self) { group in
            for subjectID in Set(subjectIDs) {
                group.addTask {
                    let isAllowed = await TopShelfProductionRegionResolver.shared.isAllowed(
                        subjectID: subjectID
                    )
                    return (subjectID, isAllowed)
                }
            }

            var allowed = Set<Int>()
            for await (subjectID, isAllowed) in group where isAllowed {
                allowed.insert(subjectID)
            }
            return allowed
        }
    }
}

private actor TopShelfProductionRegionResolver {
    static let shared = TopShelfProductionRegionResolver()

    private var allowedBySubjectID: [Int: Bool] = [:]

    func isAllowed(subjectID: Int) async -> Bool {
        if let cached = allowedBySubjectID[subjectID] {
            return cached
        }

        do {
            let bangumi = try await BangumiAPI.shared.getBangumiInfo(id: subjectID)
            let isChineseProduction = TopShelfRegionPolicy.isChineseProduction(
                metaTags: [],
                tags: bangumi.tags.map(\.name)
            )
            let isAllowed = !isChineseProduction
            allowedBySubjectID[subjectID] = isAllowed
            return isAllowed
        } catch {
            print(
                "TopShelfProductionRegionResolver: failed to classify subject "
                    + "\(subjectID): \(error.localizedDescription)"
            )
            return false
        }
    }
}
