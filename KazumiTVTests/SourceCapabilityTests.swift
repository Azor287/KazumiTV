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
        XCTAssertEqual(capability.badgeTitle, "本地")
    }

    func testRecommendedXfdmneoIsClassifiedAsLocalPlayback() {
        let capability = SourceCapabilityRegistry.capability(forPluginName: "xfdmneo")

        XCTAssertTrue(capability.supportsLocalPlayback)
        XCTAssertFalse(capability.requiresBrowserRuntime)
        XCTAssertEqual(capability.badgeTitle, "本地")
    }

    func testActiveCaptchaRulesUseLocalBrowserRuntimeWithoutExternalResolver() {
        let capability = SourceCapabilityRegistry.capability(forPluginName: "mgnacg")

        XCTAssertTrue(capability.requiresBrowserRuntime)
        XCTAssertFalse(capability.allowExternalResolver)
    }

    func testActiveAPI8RuleIsClassifiedAsLocalPlayback() {
        let capability = SourceCapabilityRegistry.capability(forPluginName: "sorani")

        XCTAssertTrue(capability.supportsLocalPlayback)
        XCTAssertFalse(capability.requiresBrowserRuntime)
    }
}
