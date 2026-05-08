//
//  TimelineViewModel.swift
//  KazumiTV
//
//  Timeline ViewModel - handles weekly anime schedule
//

import Foundation
import Combine

@MainActor
class TimelineViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var calendar: [[Bangumi]] = Array(repeating: [], count: 7)
    @Published var selectedWeekday: Int = 1  // 1 = Monday
    @Published var sortType: TimelineSortType = .time
    @Published var notShowAbandonedBangumis = false
    @Published var notShowWatchedBangumis = false
    @Published var isLoading = false
    @Published var error: Error?
    @Published private var abandonedBangumiIDs: Set<Int> = []
    @Published private var watchedBangumiIDs: Set<Int> = []

    // MARK: - Services
    private let bangumiAPI = BangumiAPI.shared
    private let favoriteRepository = FavoriteRepository.shared
    private let settings = SettingsRepository.shared
    private var hasLoadedData = false

    // MARK: - Weekday Names
    let weekdayNames = [
        (1, "一"),
        (2, "二"),
        (3, "三"),
        (4, "四"),
        (5, "五"),
        (6, "六"),
        (7, "日")
    ]

    // MARK: - Computed Properties

    var selectedDayBangumis: [Bangumi] {
        bangumis(for: selectedWeekday)
    }

    var hasActiveFilters: Bool {
        notShowAbandonedBangumis || notShowWatchedBangumis
    }

    func bangumis(for weekday: Int) -> [Bangumi] {
        guard weekday >= 1 && weekday <= 7 else { return [] }
        var items = calendar[weekday - 1]

        if notShowAbandonedBangumis {
            items.removeAll { abandonedBangumiIDs.contains($0.id) }
        }

        if notShowWatchedBangumis {
            items.removeAll { watchedBangumiIDs.contains($0.id) }
        }

        switch sortType {
        case .time:
            return items.sorted { $0.id < $1.id }
        case .score:
            return items.sorted {
                if $0.ratingScore == $1.ratingScore {
                    return $0.id < $1.id
                }
                return $0.ratingScore > $1.ratingScore
            }
        case .heat:
            return items.sorted {
                if $0.votes == $1.votes {
                    return $0.id < $1.id
                }
                return $0.votes > $1.votes
            }
        }
    }

    var todayWeekday: Int {
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: Date())
        return weekday == 1 ? 7 : weekday - 1
    }

    // MARK: - Init

    init() {
        // Set initial weekday to today
        selectedWeekday = todayWeekday
        notShowAbandonedBangumis = settings.getBool(.timelineNotShowAbandonedBangumis)
        notShowWatchedBangumis = settings.getBool(.timelineNotShowWatchedBangumis)
    }

    // MARK: - Load Data

    func loadData() async {
        isLoading = true
        error = nil

        do {
            calendar = try await bangumiAPI.getCalendar()
            await loadCollectionFilterIDs()
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

    // MARK: - Select Weekday

    func selectWeekday(_ weekday: Int) {
        guard weekday >= 1 && weekday <= 7 else { return }
        selectedWeekday = weekday
    }

    func selectNextDay() {
        selectedWeekday = selectedWeekday % 7 + 1
    }

    func selectPreviousDay() {
        selectedWeekday = selectedWeekday == 1 ? 7 : selectedWeekday - 1
    }

    func changeSortType(_ sortType: TimelineSortType) {
        self.sortType = sortType
    }

    func setNotShowAbandonedBangumis(_ value: Bool) {
        notShowAbandonedBangumis = value
        settings.setBool(.timelineNotShowAbandonedBangumis, value)
        if value {
            Task {
                await loadCollectionFilterIDs()
            }
        }
    }

    func setNotShowWatchedBangumis(_ value: Bool) {
        notShowWatchedBangumis = value
        settings.setBool(.timelineNotShowWatchedBangumis, value)
        if value {
            Task {
                await loadCollectionFilterIDs()
            }
        }
    }

    // MARK: - Refresh

    func refresh() async {
        await loadData()
    }

    private func loadCollectionFilterIDs() async {
        do {
            let collections = try await favoriteRepository.getCollections()
            abandonedBangumiIDs = Set(
                collections
                    .filter { $0.type == FavoriteRepository.CollectionType.dropped.rawValue }
                    .map(\.bangumiId)
            )
            watchedBangumiIDs = Set(
                collections
                    .filter { $0.type == FavoriteRepository.CollectionType.watched.rawValue }
                    .map(\.bangumiId)
            )
        } catch {
            print("TimelineViewModel: failed to load collection filters: \(error.localizedDescription)")
        }
    }
}

enum TimelineSortType: Int, CaseIterable, Identifiable {
    case time = 1
    case score = 2
    case heat = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .time: return "时间优先"
        case .score: return "评分优先"
        case .heat: return "热度优先"
        }
    }

    var icon: String {
        switch self {
        case .time: return "clock"
        case .score: return "star.fill"
        case .heat: return "flame.fill"
        }
    }
}
