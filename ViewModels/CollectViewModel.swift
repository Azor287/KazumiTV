//
//  CollectViewModel.swift
//  KazumiTV
//
//  Collection/Favorites ViewModel
//

import Foundation
import Combine

@MainActor
class CollectViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var collections: [CollectedBangumi] = []
    @Published var isLoading = false
    @Published var error: Error?

    // MARK: - Filter
    @Published var selectedFilter: CollectionFilter = .all

    enum CollectionFilter: String, CaseIterable {
        case all = "全部"
        case watching = "在看"
        case wantToWatch = "想看"
        case onHold = "搁置"
        case watched = "看过"
        case dropped = "抛弃"

        var typeValue: Int? {
            switch self {
            case .all: return nil
            case .watching: return 1
            case .wantToWatch: return 2
            case .onHold: return 3
            case .watched: return 4
            case .dropped: return 5
            }
        }
    }

    // MARK: - Services
    private let favoriteRepository = FavoriteRepository.shared
    private var hasLoadedData = false

    // MARK: - Computed Properties

    var filteredCollections: [CollectedBangumi] {
        switch selectedFilter {
        case .all:
            return collections
        default:
            guard let typeValue = selectedFilter.typeValue else { return collections }
            return collections.filter { $0.type == typeValue }
        }
    }

    // MARK: - Init

    init() {}

    // MARK: - Load Data

    func loadData() async {
        isLoading = true
        error = nil

        do {
            collections = try await favoriteRepository.getCollections()
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

    // MARK: - Add/Remove

    func addToCollection(bangumi: Bangumi, type: CollectionFilter = .watching) async {
        guard let typeValue = type.typeValue else { return }

        do {
            try await favoriteRepository.addToCollection(bangumi: bangumi, type: FavoriteRepository.CollectionType(rawValue: typeValue) ?? .watching)
            await loadData()
        } catch {
            self.error = error
        }
    }

    func removeFromCollection(bangumiId: Int) async {
        do {
            try await favoriteRepository.removeFromCollection(bangumiId: bangumiId)
            await loadData()
        } catch {
            self.error = error
        }
    }

    func updateWatchProgress(bangumiId: Int, episode: Int, progress: Double) async {
        do {
            try await favoriteRepository.updateWatchProgress(bangumiId: bangumiId, episode: episode, progress: progress)
        } catch {
            print("Failed to update watch progress: \(error)")
        }
    }

    // MARK: - Check

    func isCollected(bangumiId: Int) -> Bool {
        return collections.contains { $0.bangumiId == bangumiId }
    }

    // MARK: - Refresh

    func refresh() async {
        await loadData()
    }
}
