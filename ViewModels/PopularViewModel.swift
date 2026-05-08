//
//  PopularViewModel.swift
//  KazumiTV
//
//  Popular ViewModel - handles trending/popular content
//

import Foundation
import Combine

@MainActor
class PopularViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var popularBangumis: [Bangumi] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: Error?

    // MARK: - Pagination
    private var currentOffset = 0
    private let pageSize = 24
    private var hasMore = true
    private var hasLoadedData = false

    // MARK: - Services
    private let bangumiAPI = BangumiAPI.shared

    // MARK: - Init

    init() {}

    // MARK: - Load Data

    func loadData() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        currentOffset = 0

        do {
            let results = try await bangumiAPI.getTrends(limit: pageSize, offset: 0)
            popularBangumis = results
            hasMore = results.count >= pageSize
            currentOffset = results.count
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

    // MARK: - Load More

    func loadMore() async {
        guard !isLoadingMore && hasMore else { return }

        isLoadingMore = true

        do {
            let results = try await bangumiAPI.getTrends(limit: pageSize, offset: currentOffset)
            popularBangumis.append(contentsOf: results)
            hasMore = results.count >= pageSize
            currentOffset += results.count
        } catch {
            print("Failed to load more: \(error)")
        }

        isLoadingMore = false
    }

    // MARK: - Refresh

    func refresh() async {
        await loadData()
    }
}
