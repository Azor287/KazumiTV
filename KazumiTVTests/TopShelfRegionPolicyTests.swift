import XCTest
@testable import KazumiTV

final class TopShelfRegionPolicyTests: XCTestCase {
    func testBlocksChineseProductionMetaTag() {
        XCTAssertTrue(
            TopShelfRegionPolicy.isChineseProduction(
                metaTags: ["原创", "中国", "WEB"],
                tags: []
            )
        )
    }

    func testBlocksChineseProductionRegularTag() {
        XCTAssertTrue(
            TopShelfRegionPolicy.isChineseProduction(
                metaTags: [],
                tags: ["动画", "中国大陆"]
            )
        )
    }

    func testAllowsJapaneseProduction() {
        XCTAssertFalse(
            TopShelfRegionPolicy.isChineseProduction(
                metaTags: ["TV", "日本"],
                tags: ["漫画改"]
            )
        )
    }

    func testLegacySharedSnapshotDefaultsToBlocked() throws {
        let json = """
        {
          "identifier": "legacy",
          "subjectID": 1,
          "title": "Legacy",
          "contextTitle": "播放历史",
          "summary": "",
          "imageURL": "",
          "updatedAt": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let item = try decoder.decode(TopShelfSharedItem.self, from: json)

        XCTAssertTrue(item.isChineseProduction)
    }
}
