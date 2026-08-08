import Foundation
import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    private static let fallbackImageURL = Bundle.main.url(
        forResource: "top-shelf-wide",
        withExtension: "png"
    )

    override func loadTopShelfContent(
        completionHandler: @escaping ((any TVTopShelfContent)?) -> Void
    ) {
        let source = TopShelfSharedStore.source
        var items = TopShelfSharedStore.items(for: source)
            .filter { !$0.isChineseProduction }
        if items.isEmpty, source != .recentUpdates {
            items = TopShelfSharedStore.items(for: .recentUpdates)
                .filter { !$0.isChineseProduction }
        }
        if !items.isEmpty {
            completionHandler(Self.makeContent(from: Array(items.prefix(8))))
            return
        }

        Task {
            let remoteItems = await withTaskGroup(
                of: [TopShelfSharedItem]?.self,
                returning: [TopShelfSharedItem]?.self
            ) { group in
                group.addTask {
                    try? await TopShelfRemoteSyncService.fetch(
                        source == .seasonal ? .seasonal : .recentUpdates
                    )
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            completionHandler(Self.makeContent(from: Array((remoteItems ?? []).prefix(8))))
        }
    }

    private static func makeContent(from sharedItems: [TopShelfSharedItem]) -> TVTopShelfContent? {
        let items = sharedItems.map { shared in
            let item = TVTopShelfCarouselItem(identifier: shared.identifier)
            item.title = shared.title
            item.contextTitle = shared.contextTitle
            item.summary = shared.summary
            setImage(on: item, imageURL: secureURL(shared.imageURL))
            setAction(on: item, subjectID: shared.subjectID)
            return item
        }
        return makeCarouselContent(items: items)
    }

    private static func makeCarouselContent(items: [TVTopShelfCarouselItem]) -> TVTopShelfContent? {
        if !items.isEmpty {
            return TVTopShelfCarouselContent(style: .details, items: items)
        }

        let fallback = TVTopShelfCarouselItem(identifier: "kazumitv-fallback")
        fallback.title = "KazumiTV"
        fallback.contextTitle = "最近更新"
        fallback.summary = "打开 KazumiTV，发现最近更新的动画。"
        setImage(on: fallback, imageURL: fallbackImageURL)
        return TVTopShelfCarouselContent(style: .details, items: [fallback])
    }

    private static func setImage(on item: TVTopShelfCarouselItem, imageURL: URL?) {
        if let imageURL = imageURL ?? fallbackImageURL {
            item.setImageURL(imageURL, for: [.screenScale1x, .screenScale2x])
        }
    }

    private static func setAction(on item: TVTopShelfCarouselItem, subjectID: Int) {
        if let actionURL = URL(string: "kazumitv://subject/\(subjectID)") {
            item.displayAction = TVTopShelfAction(url: actionURL)
        }
    }

    private static func secureURL(_ rawValue: String?) -> URL? {
        guard var rawValue, !rawValue.isEmpty else { return nil }
        if rawValue.hasPrefix("//") {
            rawValue = "https:" + rawValue
        } else if rawValue.hasPrefix("http://") {
            rawValue = "https://" + rawValue.dropFirst("http://".count)
        }
        return URL(string: rawValue)
    }
}
