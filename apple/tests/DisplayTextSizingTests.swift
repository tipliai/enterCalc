import XCTest
@testable import EnterCalcCore

final class DisplayTextSizingTests: XCTestCase {
    // iPhone portrait base sizes.
    private let baseResult: CGFloat = 56
    private let baseOperation: CGFloat = 15
    private let spacing: CGFloat = 6

    private func scale(contentHeight: CGFloat, contentWidth: CGFloat = 10_000) -> CGFloat {
        DisplayTextSizing.scale(
            contentHeight: contentHeight,
            contentWidth: contentWidth,
            baseResultFontSize: baseResult,
            baseOperationFontSize: baseOperation,
            spacing: spacing
        )
    }

    private func sizes(
        contentHeight: CGFloat,
        contentWidth: CGFloat = 10_000,
        textScale: CGFloat = 1
    ) -> DisplayTextSizing.FontSizes {
        DisplayTextSizing.fontSizes(
            contentHeight: contentHeight,
            contentWidth: contentWidth,
            baseResultFontSize: baseResult,
            baseOperationFontSize: baseOperation,
            spacing: spacing,
            textScale: textScale
        )
    }

    private func stackHeight(_ sizes: DisplayTextSizing.FontSizes) -> CGFloat {
        sizes.result * 1.12 + sizes.operation * 1.3 + spacing
    }

    // MARK: Growing with the display (#136)

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

    func testGrownTextFitsTheFillShareOfTheHeight() {
        let contentHeight: CGFloat = 170
        let factor = scale(contentHeight: contentHeight)
        let stack = baseResult * factor * 1.12 + baseOperation * factor * 1.3 + spacing
        XCTAssertEqual(stack, contentHeight * DisplayTextSizing.fillRatio, accuracy: 0.001)
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
        XCTAssertLessThan(narrow, wide)
        XCTAssertEqual(baseResult * narrow * DisplayTextSizing.referenceResultWidthInEms, 260, accuracy: 0.001)
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

    // MARK: No fixed ceiling, and the Text Size setting (#148)

    func testGrowthHasNoFixedCeiling() {
        // A display dragged much taller keeps growing the text; #136 stopped at 1.6x.
        XCTAssertGreaterThan(scale(contentHeight: 600), 2)
        XCTAssertGreaterThan(scale(contentHeight: 800), scale(contentHeight: 600))
    }

    func testDefaultTextScaleMatchesTheSpaceScale() {
        let result = sizes(contentHeight: 170)
        XCTAssertEqual(result.result, baseResult * scale(contentHeight: 170), accuracy: 0.001)
    }

    func testLargerTextSizeGrowsTheResult() {
        let standard = sizes(contentHeight: 170)
        let large = sizes(contentHeight: 170, textScale: 21.0 / 17.0)
        XCTAssertGreaterThan(large.result, standard.result)
    }

    func testSmallerTextSizeShrinksTheResultEvenInACrampedDisplay() {
        let small = sizes(contentHeight: 60, textScale: 14.0 / 17.0)
        XCTAssertEqual(small.result, baseResult * 14.0 / 17.0, accuracy: 0.001)
    }

    func testLargestTextSizeNeverOverflowsTheDisplayHeight() {
        let contentHeight: CGFloat = 170
        let extraLarge = sizes(contentHeight: contentHeight, textScale: 28.0 / 17.0)
        XCTAssertLessThanOrEqual(
            stackHeight(extraLarge),
            contentHeight * DisplayTextSizing.maximumFillRatio + 0.001
        )
        XCTAssertGreaterThan(extraLarge.result, sizes(contentHeight: contentHeight).result)
    }

    func testOperationLineGrowsWithTheResultUpToItsCap() {
        let modest = sizes(contentHeight: 170)
        XCTAssertEqual(modest.operation / baseOperation, modest.result / baseResult, accuracy: 0.001)

        let huge = sizes(contentHeight: 2_000)
        XCTAssertEqual(huge.operation, baseOperation * DisplayTextSizing.maximumOperationScale, accuracy: 0.001)
    }
}
