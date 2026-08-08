import Foundation
import XCTest
@testable import KazumiTV

final class TransientNetworkRetryTests: XCTestCase {
    func testRetriesHandshakeResetWithoutPeerTrustFailure() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.secureConnectionFailed.rawValue
        )

        XCTAssertTrue(TransientNetworkRetry.shouldRetry(error))
    }

    func testDoesNotRetryCertificateTrustFailure() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.secureConnectionFailed.rawValue,
            userInfo: [NSURLErrorFailingURLPeerTrustErrorKey: "untrusted"]
        )

        XCTAssertFalse(TransientNetworkRetry.shouldRetry(error))
    }

    func testDoesNotRetryCancellation() {
        XCTAssertFalse(TransientNetworkRetry.shouldRetry(URLError(.cancelled)))
    }
}
