//
//  HomeViewModel.swift
//  KazumiTV
//
//  Home ViewModel - handles calendar, trends, and featured content
//

import Foundation
import Combine

struct HomeBangumiCategory: Identifiable, Hashable {
    let title: String
    let tag: String?

    var id: String {
        tag ?? title
    }

    static let all: [HomeBangumiCategory] = [
        HomeBangumiCategory(title: "热门番组", tag: nil),
        HomeBangumiCategory(title: "原创", tag: "原创"),
        HomeBangumiCategory(title: "漫画改", tag: "漫画改"),
        HomeBangumiCategory(title: "小说改", tag: "小说改"),
        HomeBangumiCategory(title: "游戏改", tag: "游戏改"),
        HomeBangumiCategory(title: "奇幻", tag: "奇幻"),
        HomeBangumiCategory(title: "科幻", tag: "科幻"),
        HomeBangumiCategory(title: "日常", tag: "日常"),
        HomeBangumiCategory(title: "恋爱", tag: "恋爱"),
        HomeBangumiCategory(title: "校园", tag: "校园"),
        HomeBangumiCategory(title: "战斗", tag: "战斗"),
        HomeBangumiCategory(title: "搞笑", tag: "搞笑"),
        HomeBangumiCategory(title: "治愈", tag: "治愈"),
        HomeBangumiCategory(title: "百合", tag: "百合")
    ]
}

@MainActor
class HomeViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var calendar: [[Bangumi]] = Array(repeating: [], count: 7)
    @Published var trends: [Bangumi] = []
    @Published var featuredBangumis: [Bangumi] = []
    @Published var selectedCategory = HomeBangumiCategory.all[0]
    @Published var isLoading = false
    @Published var isLoadingTrends = false
    @Published var isLoadingMore = false
    @Published var error: Error?

    // MARK: - Pagination
    private var currentOffset = 0
    private let pageSize = 20
    private var hasMore = true

    // MARK: - Services
    private let bangumiAPI = BangumiAPI.shared

    // MARK: - Weekday Names
    let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    // MARK: - Init

    init() {}

    // MARK: - Load Data

    func loadData(force: Bool = false) async {
        guard force || trends.isEmpty else { return }
        guard !isLoading else { return }

        isLoading = true
        error = nil

        await loadTrends()

        isLoading = false
    }

    func loadCalendar() async {
        do {
            let result = try await bangumiAPI.getCalendar()
            calendar = result
        } catch {
            self.error = error
            // Fallback: try to load via search
            await loadCalendarBySearch()
        }
    }

    private func loadCalendarBySearch() async {
        // Fallback to searching for recent anime if calendar fails
        do {
            let result = try await bangumiAPI.search(keyword: "", limit: 100, offset: 0)
            self.calendar = Array(repeating: result, count: 7)
        } catch {
            self.error = error
        }
    }

    private func getSeasonStart() -> Date {
        let calendar = Calendar(identifier: .chinese)
        let now = Date()
        let month = calendar.component(.month, from: now)

        var startMonth: Int
        if month >= 10 {
            startMonth = 10
        } else if month >= 7 {
            startMonth = 7
        } else if month >= 4 {
            startMonth = 4
        } else {
            startMonth = 1
        }

        var components = calendar.dateComponents([.year], from: now)
        components.month = startMonth
        components.day = 1

        return calendar.date(from: components) ?? now
    }

    private func getSeasonEnd(_ start: Date) -> Date {
        let calendar = Calendar(identifier: .chinese)
        return calendar.date(byAdding: .month, value: 3, to: start) ?? start
    }

    func loadTrends() async {
        isLoadingTrends = true
        error = nil
        currentOffset = 0
        hasMore = true
        trends = []
        featuredBangumis = []

        do {
            let result = try await loadBangumis(limit: pageSize, offset: 0)
            trends = result
            featuredBangumis = Array(result.prefix(5))
            hasMore = result.count >= pageSize
            currentOffset = result.count
            if result.isEmpty {
                self.error = APIError.invalidResponse
            }
        } catch {
            print("Failed to load trends: \(error)")
            self.error = error
        }

        isLoadingTrends = false
    }

    func selectCategory(_ category: HomeBangumiCategory) async {
        selectedCategory = category
        await loadTrends()
    }

    // MARK: - Load More

    func loadMoreTrends() async {
        guard !isLoadingMore && !isLoadingTrends && hasMore else { return }

        isLoadingMore = true

        do {
            let result = try await loadBangumis(limit: pageSize, offset: currentOffset)
            trends.append(contentsOf: result)
            hasMore = result.count >= pageSize
            currentOffset += result.count
        } catch {
            print("Failed to load more trends: \(error)")
        }

        isLoadingMore = false
    }

    // MARK: - Refresh

    func refresh() async {
        await loadData(force: true)
    }

    private func loadBangumis(limit: Int, offset: Int) async throws -> [Bangumi] {
        if let tag = selectedCategory.tag {
            return try await bangumiAPI.getTaggedBangumis(tag: tag, limit: limit, offset: offset)
        }

        return try await bangumiAPI.getPopularBangumis(limit: limit, offset: offset)
    }
}
