import XCTest
@testable import EnterCalcCore

final class DisplayTextSizingTests: XCTestCase {
    private func scale(contentHeight: CGFloat, contentWidth: CGFloat = 10_000) -> CGFloat {
        // iPhone portrait base sizes.
        DisplayTextSizing.scale(
            contentHeight: contentHeight,
            contentWidth: contentWidth,
            baseResultFontSize: 56,
            baseOperationFontSize: 15,
            spacing: 6
        )
    }

    func testCrampedDisplayKeepsTheBaseSize() {
        XCTAssertEqual(scale(contentHeight: 60), 1)
        XCTAssertEqual(scale(contentHeight: 0), 1)
    }

    func testTallerDisplayGrowsTheText() {
        let shorter = scale(contentHeight: 150)
        let taller = scale(contentHeight: 190)
        XCTAssertGreaterThan(shorter, 1)
        XCTAssertGreaterThan(taller, shorter)
    }

    func testGrowthStopsAtTheMaximum() {
        XCTAssertEqual(scale(contentHeight: 2_000), DisplayTextSizing.maximumScale)
    }

    func testGrownTextFitsTheFillShareOfTheHeight() {
        let contentHeight: CGFloat = 170
        let factor = scale(contentHeight: contentHeight)
        let stackHeight = 56 * factor * 1.12 + 15 * factor * 1.3 + 6
        XCTAssertLessThan(factor, DisplayTextSizing.maximumScale)
        XCTAssertEqual(stackHeight, contentHeight * DisplayTextSizing.fillRatio, accuracy: 0.001)
    }

    func testZeroBaseSizeDoesNotDivideByZero() {
        let factor = DisplayTextSizing.scale(
            contentHeight: 200,
            contentWidth: 400,
            baseResultFontSize: 0,
            baseOperationFontSize: 15,
            spacing: 6
        )
        XCTAssertEqual(factor, 1)
    }

    func testNarrowDisplayLimitsGrowthEvenWithSpareHeight() {
        let wide = scale(contentHeight: 400)
        let narrow = scale(contentHeight: 400, contentWidth: 260)
        XCTAssertEqual(wide, DisplayTextSizing.maximumScale)
        XCTAssertLessThan(narrow, wide)
        XCTAssertEqual(56 * narrow * DisplayTextSizing.referenceResultWidthInEms, 260, accuracy: 0.001)
    }

    func testWideningANarrowDisplayGrowsTheText() {
        XCTAssertGreaterThan(
            scale(contentHeight: 400, contentWidth: 300),
            scale(contentHeight: 400, contentWidth: 260)
        )
    }

    func testTooNarrowDisplayKeepsTheBaseSize() {
        XCTAssertEqual(scale(contentHeight: 400, contentWidth: 100), 1)
    }
}
