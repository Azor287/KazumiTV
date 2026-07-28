import XCTest
@testable import KazumiTV

final class SourceCapabilityTests: XCTestCase {
    func testNativeSourcesRankAsLocallyPlayable() {
        let capability = SourceCapabilityRegistry.capability(forPluginName: "MXDM")

        XCTAssertTrue(capability.supportsLocalPlayback)
        XCTAssertFalse(capability.requiresBrowserRuntime)
    }

    func testBrowserSourcesRemainEligibleForLocalWebFallback() {
        let capability = SourceCapabilityRegistry.capability(forPluginName: "DM84")

        XCTAssertTrue(capability.requiresBrowserRuntime)
        XCTAssertFalse(capability.loginRequired)
    }
}
