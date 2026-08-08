import Foundation
import TVServices

enum TopShelfSource: String, CaseIterable, Codable, Identifiable {
    case seasonal
    case recentUpdates
    case favorites
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .seasonal: return "当季新番"
        case .recentUpdates: return "最近更新"
        case .favorites: return "用户追番"
        case .history: return "播放历史"
        }
    }

    var subtitle: String {
        switch self {
        case .seasonal: return "显示本季度开播的新番"
        case .recentUpdates: return "显示最近播出的动画，默认选项"
        case .favorites: return "显示你保存在追番中的动画"
        case .history: return "显示最近观看过的动画"
        }
    }
}

struct TopShelfSharedItem: Codable, Hashable {
    let identifier: String
    let subjectID: Int
    let title: String
    let contextTitle: String
    let summary: String
    let imageURL: String
    let updatedAt: Date
    let isChineseProduction: Bool

    init(
        identifier: String,
        subjectID: Int,
        title: String,
        contextTitle: String,
        summary: String,
        imageURL: String,
        updatedAt: Date,
        isChineseProduction: Bool = false
    ) {
        self.identifier = identifier
        self.subjectID = subjectID
        self.title = title
        self.contextTitle = contextTitle
        self.summary = summary
        self.imageURL = imageURL
        self.updatedAt = updatedAt
        self.isChineseProduction = isChineseProduction
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case subjectID
        case title
        case contextTitle
        case summary
        case imageURL
        case updatedAt
        case isChineseProduction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(String.self, forKey: .identifier)
        subjectID = try container.decode(Int.self, forKey: .subjectID)
        title = try container.decode(String.self, forKey: .title)
        contextTitle = try container.decode(String.self, forKey: .contextTitle)
        summary = try container.decode(String.self, forKey: .summary)
        imageURL = try container.decode(String.self, forKey: .imageURL)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        // Build 13 snapshots had no production-region field. Treat them as
        // blocked until the app refreshes their metadata, so upgrades cannot
        // briefly surface an unclassified Chinese production.
        isChineseProduction = try container.decodeIfPresent(
            Bool.self,
            forKey: .isChineseProduction
        ) ?? true
    }
}

enum TopShelfSharedStore {
    static let appGroupIdentifier = "group.com.kazumi.tv"

    private enum Key {
        static let source = "topShelf.source"
        static let seasonal = "topShelf.seasonal"
        static let recentUpdates = "topShelf.recentUpdates"
        static let favorites = "topShelf.favorites"
        static let history = "topShelf.history"
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static var source: TopShelfSource {
        get {
            guard let value = defaults.string(forKey: Key.source),
                  let source = TopShelfSource(rawValue: value) else {
                return .recentUpdates
            }
            return source
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.source)
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    }

    static func items(for source: TopShelfSource) -> [TopShelfSharedItem] {
        let key: String
        switch source {
        case .seasonal: key = Key.seasonal
        case .recentUpdates: key = Key.recentUpdates
        case .favorites: key = Key.favorites
        case .history: key = Key.history
        }

        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([TopShelfSharedItem].self, from: data)) ?? []
    }

    static func save(_ items: [TopShelfSharedItem], for source: TopShelfSource) {
        let key: String
        switch source {
        case .seasonal: key = Key.seasonal
        case .recentUpdates: key = Key.recentUpdates
        case .favorites: key = Key.favorites
        case .history: key = Key.history
        }

        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    }
}
