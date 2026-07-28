import XCTest
@testable import KazumiTV

final class HLSPlaylistInspectorTests: XCTestCase {
    func testAcceptsMediaPlaylistWithSegments() {
        let playlist = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXTINF:6.0,
        segment-1.ts
        #EXT-X-ENDLIST
        """

        let inspection = HLSPlaylistInspector.inspect(playlist)

        XCTAssertTrue(inspection.isLikelyPlayable)
        XCTAssertTrue(inspection.isPlaylist)
    }

    func testRejectsPlaceholderImagePlaylist() {
        let playlist = """
        #EXTM3U
        #EXT-X-TARGETDURATION:5
        #EXTINF:5.0,
        loading.gif
        #EXT-X-ENDLIST
        """

        let inspection = HLSPlaylistInspector.inspect(playlist)

        XCTAssertFalse(inspection.isLikelyPlayable)
    }
}
