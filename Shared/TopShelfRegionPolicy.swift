import Foundation

enum TopShelfRegionPolicy {
    private static let blockedProductionTags: Set<String> = [
        "中国",
        "中国大陆",
        "大陆",
        "国产动画",
        "国产动漫",
        "国漫"
    ]

    static func isChineseProduction(metaTags: [String], tags: [String]) -> Bool {
        (metaTags + tags).contains { rawTag in
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            return blockedProductionTags.contains(tag)
        }
    }
}
