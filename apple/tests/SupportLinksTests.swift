import XCTest
@testable import EnterCalcCore

final class SupportLinksTests: XCTestCase {
    // Also published in README.md; if one moves, both should.
    func testSupportURLMatchesThePublishedSupportPage() {
        XCTAssertEqual(
            SupportLinks.supportURL.absoluteString,
            "https://tipliai.github.io/enterCalc/support/"
        )
    }

    func testSupportURLIsSecure() {
        XCTAssertEqual(SupportLinks.supportURL.scheme, "https")
    }
}
