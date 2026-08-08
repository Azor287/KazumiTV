import Foundation

enum TopShelfRemoteSyncService {
    static func syncAll() async {
        async let recent = try? fetch(.recentUpdates)
        async let seasonal = try? fetch(.seasonal)
        let results = await (recent, seasonal)
        if let items = results.0 { saveIfUsable(items, for: .recentUpdates) }
        if let items = results.1 { saveIfUsable(items, for: .seasonal) }
    }

    static func fetch(_ source: TopShelfSource) async throws -> [TopShelfSharedItem] {
        switch source {
        case .seasonal:
            return try await fetchSeasonal()
        case .recentUpdates, .favorites, .history:
            return try await fetchRecentUpdates()
        }
    }

    private static func fetchRecentUpdates() async throws -> [TopShelfSharedItem] {
        var request = URLRequest(url: URL(string: "https://next.bgm.tv/p1/calendar")!)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("KazumiTV/0.2.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.invalidResponse
        }
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: Date())
        let today = weekday == 1 ? 7 : weekday - 1
        let dayOrder = (0..<7).map { ((today - 1 - $0 + 7) % 7) + 1 }
        var seen = Set<Int>()
        var items: [TopShelfSharedItem] = []
        for day in dayOrder {
            for row in object["\(day)"] as? [[String: Any]] ?? [] {
                let subject = row["subject"] as? [String: Any] ?? row
                guard let item = item(from: subject, source: .recentUpdates),
                      seen.insert(item.subjectID).inserted else { continue }
                items.append(item)
            }
        }
        return Array(items.prefix(20))
    }

    private static func fetchSeasonal() async throws -> [TopShelfSharedItem] {
        var request = URLRequest(url: URL(string: "https://api.bgm.tv/v0/search/subjects?limit=50&offset=0")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("KazumiTV/0.2.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "keyword": "", "sort": "heat",
            "filter": [
                "type": [2], "air_date": seasonDateRange(),
                "rank": [">=0", "<=99999"], "nsfw": false
            ]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["data"] as? [[String: Any]] else {
            throw SyncError.invalidResponse
        }
        return Array(rows.compactMap { item(from: $0, source: .seasonal) }.prefix(20))
    }

    private static func item(from row: [String: Any], source: TopShelfSource) -> TopShelfSharedItem? {
        let id = (row["id"] as? Int) ?? Int("\(row["id"] ?? "")")
        guard let id, id > 0 else { return nil }
        let tags = (row["tags"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let metaTags = (row["metaTags"] as? [String]) ?? (row["meta_tags"] as? [String]) ?? []
        guard !TopShelfRegionPolicy.isChineseProduction(metaTags: metaTags, tags: tags) else { return nil }

        let images = row["images"] as? [String: Any]
        let imageURL = normalizedImageURL(
            (images?["large"] as? String) ?? (images?["common"] as? String)
                ?? (images?["medium"] as? String) ?? ""
        )
        let nameCN = (row["name_cn"] as? String) ?? (row["nameCN"] as? String)
        let name = row["name"] as? String
        let rating = row["rating"] as? [String: Any]
        let score = (rating?["score"] as? Double) ?? Double("\(rating?["score"] ?? 0)") ?? 0
        return TopShelfSharedItem(
            identifier: "\(source.rawValue)-\(id)", subjectID: id,
            title: (nameCN?.isEmpty == false ? nameCN : name) ?? "动画",
            contextTitle: score > 0 ? "\(source.title) · \(String(format: "%.1f", score)) 分" : source.title,
            summary: (row["summary"] as? String) ?? (row["info"] as? String) ?? "",
            imageURL: imageURL, updatedAt: Date(), isChineseProduction: false
        )
    }

    private static func saveIfUsable(_ items: [TopShelfSharedItem], for source: TopShelfSource) {
        var seen = Set<Int>()
        let result = items.filter { seen.insert($0.subjectID).inserted }.prefix(20)
        guard !result.isEmpty else { return }
        TopShelfSharedStore.save(Array(result), for: source)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else { throw SyncError.invalidResponse }
    }

    private static func normalizedImageURL(_ value: String) -> String {
        if value.hasPrefix("//") { return "https:" + value }
        if value.hasPrefix("http://") { return "https://" + value.dropFirst("http://".count) }
        return value
    }

    private static func seasonDateRange(now: Date = Date()) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let startMonth = ((month - 1) / 3) * 3 + 1
        let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? now
        let end = calendar.date(byAdding: .month, value: 3, to: start) ?? now
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return [">=\(formatter.string(from: start))", "<\(formatter.string(from: end))"]
    }

    private enum SyncError: Error { case invalidResponse }
}
