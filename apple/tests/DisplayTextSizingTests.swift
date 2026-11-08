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

    func testSmallerTextSizeAlsoShrinksACappedOperationLine() {
        let standard = sizes(contentHeight: 2_000)
        let small = sizes(contentHeight: 2_000, textScale: 14.0 / 17.0)
        XCTAssertLessThan(small.operation, standard.operation)
        XCTAssertEqual(
            small.operation,
            baseOperation * DisplayTextSizing.maximumOperationScale * 14.0 / 17.0,
            accuracy: 0.001
        )
    }

    // MARK: Operation line wrapping (iPhone SE at large text sizes)

    func testOperationLineKeepsTheClosingSignWithTheLastNumber() {
        XCTAssertEqual(DisplayTextSizing.operationLineText("12 × 3 ="), "12 × 3\u{00A0}=")
        XCTAssertEqual(DisplayTextSizing.operationLineText("=round(4.33, 1) ≈"), "=round(4.33, 1)\u{00A0}≈")
    }

    func testOperationLineLeavesOperatorSpacesBreakable() {
        XCTAssertEqual(DisplayTextSizing.operationLineText("12 ×"), "12 ×")
        XCTAssertEqual(DisplayTextSizing.operationLineText("1,234 + 5"), "1,234 + 5")
        XCTAssertEqual(DisplayTextSizing.operationLineText(""), "")
        XCTAssertEqual(DisplayTextSizing.operationLineText("="), "=")
    }

    func testOperationLineKeepsFrenchGroupedNumbersWhole() {
        // French grouping uses a plain space between digit groups.
        XCTAssertEqual(
            DisplayTextSizing.operationLineText("1 234 567 × 9 876 ="),
            "1\u{00A0}234\u{00A0}567 × 9\u{00A0}876\u{00A0}="
        )
    }

    /// Each character is 0.6 of the font size wide.
    private func fakeWidth(_ run: String, at fontSize: CGFloat) -> CGFloat {
        CGFloat(run.count) * fontSize * 0.6
    }

    func testOperationFontSizeIsUnchangedWhenEveryNumberFits() {
        let size = DisplayTextSizing.operationFontSize(20, fitting: "12 × 3\u{00A0}=", width: 300) { fakeWidth($0, at: 20) }
        XCTAssertEqual(size, 20)
    }

    func testOperationFontSizeShrinksUntilTheWidestNumberFits() {
        // "1,234,567,890,123,456" is 21 characters: 21 × 34 × 0.6 = 428.4 wide.
        let text = DisplayTextSizing.operationLineText("1,234,567,890,123,456 × 9,876,543 =")
        let size = DisplayTextSizing.operationFontSize(34, fitting: text, width: 311) { fakeWidth($0, at: 34) }
        XCTAssertEqual(size, 34 * 311 / 428.4, accuracy: 0.01)
        XCTAssertLessThan(size, 34)
    }

    func testOperationFontSizeMeasuresTheClosingSignWithItsNumber() {
        // "9,876,543\u{00A0}=" is one run of 11 characters.
        let size = DisplayTextSizing.operationFontSize(10, fitting: "1 × 9,876,543\u{00A0}=", width: 60) { fakeWidth($0, at: 10) }
        XCTAssertEqual(size, 10 * 60 / 66, accuracy: 0.001)
    }

    func testOperationFontSizeNeverShrinksBelowTheMinimum() {
        let size = DisplayTextSizing.operationFontSize(20, fitting: String(repeating: "9", count: 100), width: 50) { fakeWidth($0, at: 20) }
        XCTAssertEqual(size, 10)
    }

    // A history result shrinks onto one line while it can; one too wide even
    // at the smallest scale (an expanded 41-digit result in the landscape
    // column) wraps instead of being cut off.
    func testResultFitsOnOneLineOnlyWhileTheMinimumScaleFitsIt() {
        XCTAssertTrue(DisplayTextSizing.fitsOnOneLine(textWidth: 400, in: 200, minimumScale: 0.3))
        XCTAssertFalse(DisplayTextSizing.fitsOnOneLine(textWidth: 900, in: 200, minimumScale: 0.3))
        // The margin for SwiftUI's wider layout applies here too.
        XCTAssertFalse(DisplayTextSizing.fitsOnOneLine(textWidth: 200, in: 200, minimumScale: 1))
    }

    // A long result reused as an operand, too wide to fit even at the floor,
    // gets the floor size; the line then breaks inside it, keeping every digit.
    func testLongReusedResultStopsAtTheFloorSize() {
        let line = DisplayTextSizing.operationLineText("12,345,678,912,345,670,000,000,000,000,000 + 1 =")
        let size = DisplayTextSizing.operationFontSize(20, fitting: line, width: 100, minimumScale: 0.5) { run in
            CGFloat(run.count) * 10
        }
        XCTAssertEqual(size, 10)
    }
}
