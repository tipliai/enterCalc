import XCTest
@testable import EnterCalcCore

final class AppStoreLinksTests: XCTestCase {
    // The App Store ID also appears in README.md; if one changes, both should.
    func testAppIDMatchesPublishedListing() {
        XCTAssertEqual(AppStoreLinks.appID, "6777242723")
    }

    func testProductURLPointsAtTheListing() {
        XCTAssertEqual(
            AppStoreLinks.productURL.absoluteString,
            "https://apps.apple.com/app/id6777242723"
        )
    }

    // The action query is what opens the review sheet directly instead of just
    // landing on the product page.
    func testWriteReviewURLRequestsTheReviewSheet() {
        XCTAssertEqual(
            AppStoreLinks.writeReviewURL.absoluteString,
            "https://apps.apple.com/app/id6777242723?action=write-review"
        )
    }
}
