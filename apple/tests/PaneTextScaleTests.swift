import XCTest
@testable import EnterCalcCore

/// The overlay panes' text scale (#152).
final class PaneTextScaleTests: XCTestCase {
    func testChosenSizeWinsOverTheSystemSize() {
        XCTAssertEqual(PaneTextScale.resolved(.standard, systemScale: 1.5), 1)
        XCTAssertEqual(PaneTextScale.resolved(.extraLarge, systemScale: 1), 28.0 / 17.0, accuracy: 0.0001)
        XCTAssertEqual(PaneTextScale.resolved(.extraSmall, systemScale: 1), 14.0 / 17.0, accuracy: 0.0001)
    }

    func testFollowingTheSystemUsesItsScale() {
        XCTAssertEqual(PaneTextScale.resolved(.system, systemScale: 1.3), 1.3, accuracy: 0.0001)
    }

    func testAccessibilitySizesStopGrowingAtTheMaximum() {
        // Past this the panes scroll instead of growing further.
        XCTAssertEqual(PaneTextScale.resolved(.system, systemScale: 3.1), PaneTextScale.maximum)
    }

    func testScaleNeverGoesBelowExtraSmallOrBecomesInvalid() {
        XCTAssertEqual(PaneTextScale.resolved(.system, systemScale: 0.5), PaneTextScale.minimum)
        XCTAssertEqual(PaneTextScale.resolved(.system, systemScale: .nan), 1)
        XCTAssertEqual(PaneTextScale.resolved(.system, systemScale: 0), 1)
    }

    func testControlsGrowWithTextButNeverShrinkBelowTheirSize() {
        XCTAssertEqual(PaneTextScale.grown(44, by: 0.8), 44)
        XCTAssertEqual(PaneTextScale.grown(44, by: 1.5), 66)
        XCTAssertEqual(PaneTextScale.scaled(13, by: 0.8), 10)
    }
}
