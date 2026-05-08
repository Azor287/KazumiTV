//
//  SearchViewModel.swift
//  KazumiTV
//
//  Search ViewModel
//

import Foundation
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var searchText = ""
    @Published var searchResults: [Bangumi] = []
    @Published var isSearching = false
    @Published var error: Error?
    @Published var recentSearches: [String] = []

    // MARK: - Services
    private let bangumiAPI = BangumiAPI.shared

    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        loadRecentSearches()
        setupSearchDebounce()
    }

    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
    }

    private func saveRecentSearch(_ query: String) {
        var searches = recentSearches
        searches.removeAll { $0 == query }
        searches.insert(query, at: 0)
        if searches.count > 20 {
            searches = Array(searches.prefix(20))
        }
        recentSearches = searches
        UserDefaults.standard.set(searches, forKey: "recentSearches")
    }

    private func setupSearchDebounce() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task {
                        await self?.search(query: query)
                    }
                } else {
                    self?.searchTask?.cancel()
                    self?.searchResults = []
                    self?.isSearching = false
                    self?.error = nil
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Search

    func search(query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            error = nil
            return
        }

        searchTask?.cancel()

        searchTask = Task {
            isSearching = true
            error = nil

            // Save to recent searches
            saveRecentSearch(query)

            do {
                let results = try await bangumiAPI.search(keyword: query)
                if !Task.isCancelled {
                    searchResults = results
                }
            } catch {
                if !Task.isCancelled {
                    self.error = error
                    searchResults = []
                }
            }

            if !Task.isCancelled {
                isSearching = false
            }
        }
    }

    // MARK: - Recent Searches

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: "recentSearches")
    }

    func removeRecentSearch(_ query: String) {
        recentSearches.removeAll { $0 == query }
        UserDefaults.standard.set(recentSearches, forKey: "recentSearches")
    }

    // MARK: - Cancel

    func cancel() {
        searchTask?.cancel()
        isSearching = false
    }
}
