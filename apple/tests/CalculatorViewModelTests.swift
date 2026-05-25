import XCTest
@testable import EnterCalcCore

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

final class CalculatorViewModelTests: XCTestCase {
    override func tearDown() {
        languageOverrideBundle = nil
        super.tearDown()
    }

    private let supportedLanguageCodes = ["en", "de", "es", "fr", "ja", "zh-Hans"]

    private struct StyleFixture {
        let style: NumberFormatStyle
        let firstOperand: String
        let secondOperand: String
        let expectedExpressionDisplay: String
        let expectedDisplay: String
        let roundingInput: String
        let roundingPrecision: Int
        let expectedRoundedDisplay: String
        let expectedRoundedOperation: String
        let expectedRoundedCopyResult: String
    }

    private func withLanguageOverride<T>(code: String, _ body: () throws -> T) throws -> T {
        let previousBundle = languageOverrideBundle
        defer { languageOverrideBundle = previousBundle }
        languageOverrideBundle = try localizedBundle(named: code)
        return try body()
    }

    private func withLanguageOverrides(_ body: (String) throws -> Void) throws {
        for code in supportedLanguageCodes {
            try withLanguageOverride(code: code) {
                try body(code)
            }
        }
    }

    private func styleFixtures() -> [StyleFixture] {
        [
            StyleFixture(
                style: .western,
                firstOperand: "2.333",
                secondOperand: "1.555",
                expectedExpressionDisplay: "2.333 + 1.555 =",
                expectedDisplay: "3.888",
                roundingInput: "3.005",
                roundingPrecision: 2,
                expectedRoundedDisplay: "3.01",
                expectedRoundedOperation: "round(3.005, 2) ≈ 3.01",
                expectedRoundedCopyResult: "3.01"
            ),
            StyleFixture(
                style: .european,
                firstOperand: "2,333",
                secondOperand: "1,555",
                expectedExpressionDisplay: "2,333 + 1,555 =",
                expectedDisplay: "3,888",
                roundingInput: "3,005",
                roundingPrecision: 2,
                expectedRoundedDisplay: "3,01",
                expectedRoundedOperation: "round(3,005; 2) ≈ 3,01",
                expectedRoundedCopyResult: "3,01"
            ),
            StyleFixture(
                style: .french,
                firstOperand: "2,333",
                secondOperand: "1,555",
                expectedExpressionDisplay: "2,333 + 1,555 =",
                expectedDisplay: "3,888",
                roundingInput: "3,005",
                roundingPrecision: 2,
                expectedRoundedDisplay: "3,01",
                expectedRoundedOperation: "round(3,005; 2) ≈ 3,01",
                expectedRoundedCopyResult: "3,01"
            ),
            StyleFixture(
                style: .swiss,
                firstOperand: "1'234.5",
                secondOperand: "2'000.1",
                expectedExpressionDisplay: "1'234.5 + 2'000.1 =",
                expectedDisplay: "3'234.6",
                roundingInput: "3.005",
                roundingPrecision: 2,
                expectedRoundedDisplay: "3.01",
                expectedRoundedOperation: "round(3.005, 2) ≈ 3.01",
                expectedRoundedCopyResult: "3.01"
            ),
            StyleFixture(
                style: .indian,
                firstOperand: "12,34,567.89",
                secondOperand: "1.11",
                expectedExpressionDisplay: "12,34,567.89 + 1.11 =",
                expectedDisplay: "12,34,569",
                roundingInput: "12,34,567.8912",
                roundingPrecision: 3,
                expectedRoundedDisplay: "12,34,567.891",
                expectedRoundedOperation: "round(12,34,567.8912, 3) ≈ 12,34,567.891",
                expectedRoundedCopyResult: "12,34,567.891"
            )
        ]
    }

#if canImport(AppKit)
    private func setClipboardString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func clipboardString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
#elseif canImport(UIKit)
    private func setClipboardString(_ string: String) {
        UIPasteboard.general.string = string
    }

    private func clipboardString() -> String? {
        UIPasteboard.general.string
    }
#endif

    private func pasteString(_ string: String, into viewModel: CalculatorViewModel) {
        setClipboardString(string)
        viewModel.pasteFromPasteboard()
    }

    func testSquareRootPlusAdditionProducesExpectedResultAndHistory() {
        let viewModel = CalculatorViewModel()

        enter("97", into: viewModel)
        viewModel.squareRoot()
        viewModel.setOperator(.add)
        enter("8", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "17.8488578017961")
        XCTAssertEqual(viewModel.expressionDisplay, "√(97) + 8 =")
        XCTAssertEqual(viewModel.history.count, 1)
        XCTAssertEqual(viewModel.history.first?.expression, "√(97) + 8")
        XCTAssertEqual(viewModel.history.first?.result, "17.8488578017961")
    }

    func testDecimalSubtractionDoesNotExposeBinaryFloatingPointResidue() {
        let viewModel = CalculatorViewModel()

        enter("123246", into: viewModel)
        viewModel.setOperator(.subtract)
        enter("105317.74", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "17,928.26")
        XCTAssertEqual(viewModel.history.first?.result, "17928.26")
    }

    func testTenthsAdditionRoundsLikeANormalCalculatorDisplay() {
        let viewModel = CalculatorViewModel()

        enter("0.1", into: viewModel)
        viewModel.setOperator(.add)
        enter("0.2", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "0.3")
        XCTAssertEqual(viewModel.history.first?.result, "0.3")
    }

    func testLargeResultUsesScientificNotationByDefault() {
        let viewModel = CalculatorViewModel()

        enter("1234567891234567", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("9999999999999999", into: viewModel)
        viewModel.evaluate()

        XCTAssertTrue(viewModel.usesScientificNotation)
        XCTAssertEqual(viewModel.display, "1.234567891234567e+31")
    }

    func testScientificNotationMatchesCalculatorForLargeIntegerProduct() {
        let viewModel = CalculatorViewModel()

        enter("99999999999", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("99999999999", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "9.9999999998e+21")
        XCTAssertEqual(viewModel.history.first?.result, "9.9999999998e+21")
    }

    func testTwoThirdsStaysInDecimalNotation() {
        let viewModel = CalculatorViewModel()

        enter("2", into: viewModel)
        viewModel.setOperator(.divide)
        enter("3", into: viewModel)
        viewModel.evaluate()

        XCTAssertFalse(viewModel.display.localizedCaseInsensitiveContains("e"))
        XCTAssertEqual(viewModel.display, "0.6666666666666667")
        XCTAssertEqual(viewModel.history.first?.result, "0.6666666666666667")
    }

    func testSmallDecimalInputsDoNotCollapseToZero() {
        let viewModel = CalculatorViewModel()

        enter("0.000000000000001", into: viewModel)
        viewModel.setOperator(.add)
        enter("0.000000000000001", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "0.000000000000002")
        XCTAssertEqual(viewModel.history.first?.result, "0.000000000000002")
    }

    func testSimpleDecimalDifferenceDoesNotSwitchToScientificNotation() {
        let viewModel = CalculatorViewModel()

        enter("1.01", into: viewModel)
        viewModel.setOperator(.subtract)
        enter("0.42", into: viewModel)
        viewModel.evaluate()

        XCTAssertFalse(viewModel.display.localizedCaseInsensitiveContains("e"))
        XCTAssertEqual(viewModel.display, "0.59")
        XCTAssertEqual(viewModel.history.first?.result, "0.59")
    }

    func testTenThirdsMatchesCalculatorRounding() {
        let viewModel = CalculatorViewModel()

        enter("10", into: viewModel)
        viewModel.setOperator(.divide)
        enter("3", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "3.333333333333333")
        XCTAssertEqual(viewModel.history.first?.result, "3.333333333333333")
    }

    func testReciprocalMatchesCalculatorRounding() {
        let viewModel = CalculatorViewModel()

        enter("7", into: viewModel)
        viewModel.reciprocal()

        XCTAssertEqual(viewModel.display, "0.1428571428571429")
    }

    func testLargeIntegerDifferenceMatchesCalculatorExactly() {
        let viewModel = CalculatorViewModel()

        enter("9999999999999999", into: viewModel)
        viewModel.setOperator(.subtract)
        enter("9999999999999998", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "1")
        XCTAssertEqual(viewModel.history.first?.result, "1")
    }

    func testScientificNotationCanBeDisabledToShowExpandedValue() {
        let viewModel = CalculatorViewModel()

        enter("1234567891234567", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("9999999999999999", into: viewModel)
        viewModel.evaluate()
        viewModel.setScientificNotationEnabled(false)

        XCTAssertFalse(viewModel.usesScientificNotation)
        XCTAssertEqual(viewModel.display, "12,345,678,912,345,670,000,000,000,000,000")
    }

    func testNumberFormatStyleCanDisplayEuropeanSeparators() {
        let viewModel = CalculatorViewModel()

        enter("1234567.89", into: viewModel)
        viewModel.setNumberFormatStyle(.european)

        XCTAssertEqual(viewModel.display, "1.234.567,89")
    }

    func testSystemLocaleDetectionMapsKnownFormats() {
        XCTAssertEqual(NumberFormatStyle.detected(from: Locale(identifier: "en_US")), .western)
        XCTAssertEqual(NumberFormatStyle.detected(from: Locale(identifier: "de_DE")), .european)
        XCTAssertEqual(NumberFormatStyle.detected(from: Locale(identifier: "fr_FR")), .french)
        XCTAssertEqual(NumberFormatStyle.detected(from: Locale(identifier: "hi_IN")), .indian)
        XCTAssertEqual(NumberFormatStyle.detected(from: Locale(identifier: "de_CH")), .swiss)
    }

    func testOperationRenderingUsesTheActiveNumberStyleAcrossAllLanguages() throws {
        try withLanguageOverrides { _ in
            for fixture in styleFixtures() {
                let viewModel = CalculatorViewModel(numberFormatStyle: fixture.style)

                pasteString(fixture.firstOperand, into: viewModel)
                viewModel.setOperator(.add)
                pasteString(fixture.secondOperand, into: viewModel)
                viewModel.evaluate()

                XCTAssertEqual(viewModel.expressionDisplay, fixture.expectedExpressionDisplay)
                XCTAssertEqual(viewModel.display, fixture.expectedDisplay)
                XCTAssertEqual(viewModel.history.first?.expression, "\(fixture.firstOperand) + \(fixture.secondOperand)")
                XCTAssertEqual(viewModel.history.first?.displayExpression, "\(fixture.firstOperand) + \(fixture.secondOperand)")
                XCTAssertEqual(viewModel.history.first?.displayResult, fixture.expectedDisplay)
            }
        }
    }

    func testParserTreatsCommaAndDecimalSeparatorsAccordingToActiveNumberStyleAcrossAllLanguages() throws {
        try withLanguageOverrides { _ in
            let western = CalculatorViewModel(numberFormatStyle: .western)
            pasteString("2,333", into: western)
            western.setOperator(.add)
            western.inputDigit("1")
            western.evaluate()
            XCTAssertEqual(western.display, "2,334")

            let european = CalculatorViewModel(numberFormatStyle: .european)
            pasteString("2,333", into: european)
            european.setOperator(.add)
            european.inputDigit("1")
            european.evaluate()
            XCTAssertEqual(european.display, "3,333")

            let french = CalculatorViewModel(numberFormatStyle: .french)
            pasteString("2,333", into: french)
            french.setOperator(.add)
            french.inputDigit("1")
            french.evaluate()
            XCTAssertEqual(french.display, "3,333")
        }
    }

    func testRoundRenderingCopyPasteAndHistoryRestorationUseNumberStyleAcrossAllLanguages() throws {
        try withLanguageOverrides { _ in
            for fixture in styleFixtures() {
                let viewModel = CalculatorViewModel(numberFormatStyle: fixture.style)

                pasteString(fixture.roundingInput, into: viewModel)
                viewModel.beginResultRounding(defaultPrecision: fixture.roundingPrecision)

                XCTAssertEqual(viewModel.display, fixture.expectedRoundedDisplay)
                XCTAssertEqual(viewModel.expressionDisplay, fixture.expectedRoundedOperation)

                viewModel.copyOperationToPasteboard()
                XCTAssertEqual(clipboardString(), fixture.expectedRoundedOperation)

                viewModel.commitResultRoundingInteraction()

                let savedEntry = try XCTUnwrap(viewModel.history.first)
                XCTAssertEqual(savedEntry.expression, fixture.expectedRoundedOperation.components(separatedBy: " ≈ ").first! + " ≈")
                XCTAssertEqual(savedEntry.displayExpression, fixture.expectedRoundedOperation.components(separatedBy: " ≈ ").first! + " ≈")
                XCTAssertEqual(savedEntry.result, fixture.expectedRoundedDisplay)
                XCTAssertEqual(savedEntry.displayResult, fixture.expectedRoundedDisplay)

                viewModel.copyResultToPasteboard(savedEntry)
                XCTAssertEqual(clipboardString(), fixture.expectedRoundedCopyResult)

                viewModel.copyOperationToPasteboard(savedEntry)
                XCTAssertEqual(clipboardString(), fixture.expectedRoundedOperation)

                let restored = CalculatorViewModel(numberFormatStyle: fixture.style)
                pasteString(fixture.expectedRoundedOperation, into: restored)

                XCTAssertEqual(restored.display, fixture.expectedRoundedDisplay)
                XCTAssertEqual(restored.expressionDisplay, fixture.expectedRoundedOperation)
                XCTAssertEqual(restored.resultRoundingPrecision, fixture.roundingPrecision)
                XCTAssertTrue(restored.isResultRoundingEnabled)
            }
        }
    }

    func testChangingNumberFormatRefreshesDisplayExpressionHistoryMemoryAndClipboard() {
        let viewModel = CalculatorViewModel(numberFormatStyle: .western)

        pasteString("1234.5", into: viewModel)
        viewModel.storeMemory()
        viewModel.setOperator(.add)
        pasteString("5.67", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "1,240.17")
        XCTAssertEqual(viewModel.expressionDisplay, "1,234.5 + 5.67 =")
        XCTAssertEqual(viewModel.history.first?.displayExpression, "1,234.5 + 5.67")
        XCTAssertEqual(viewModel.history.first?.displayResult, "1,240.17")
        XCTAssertEqual(viewModel.memoryDisplay, "1,234.5")

        viewModel.setNumberFormatStyle(.french)

        XCTAssertEqual(viewModel.display, "1 240,17")
        XCTAssertEqual(viewModel.expressionDisplay, "1 234,5 + 5,67 =")
        XCTAssertEqual(viewModel.history.first?.displayExpression, "1 234,5 + 5,67")
        XCTAssertEqual(viewModel.history.first?.displayResult, "1 240,17")
        XCTAssertEqual(viewModel.memoryDisplay, "1 234,5")

        viewModel.copyToPasteboard()
        XCTAssertEqual(clipboardString(), "1240,17")

        pasteString("2,5", into: viewModel)
        XCTAssertEqual(viewModel.display, "2,5")
    }

    func testDivideByZeroSetsLocalizedErrorState() {
        let viewModel = CalculatorViewModel()

        enter("9", into: viewModel)
        viewModel.setOperator(.divide)
        enter("0", into: viewModel)
        viewModel.evaluate()

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "Cannot divide by zero")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertTrue(viewModel.canUndo)
    }

    func testUndoAndRedoRestorePriorDisplayStates() {
        let viewModel = CalculatorViewModel()

        enter("12", into: viewModel)
        XCTAssertEqual(viewModel.display, "12")
        XCTAssertTrue(viewModel.canUndo)
        XCTAssertFalse(viewModel.canRedo)

        viewModel.undo()
        XCTAssertEqual(viewModel.display, "1")
        XCTAssertTrue(viewModel.canRedo)

        viewModel.undo()
        XCTAssertEqual(viewModel.display, "0")

        viewModel.redo()
        XCTAssertEqual(viewModel.display, "1")

        viewModel.redo()
        XCTAssertEqual(viewModel.display, "12")
        XCTAssertFalse(viewModel.canRedo)
    }

    func testInputDigitsAreCappedAtMaximumLength() {
        let viewModel = CalculatorViewModel()

        enter(String(repeating: "9", count: CalculatorViewModel.Limits.maxInputDigits + 5), into: viewModel)

        XCTAssertEqual(viewModel.display.replacingOccurrences(of: ",", with: ""), String(repeating: "9", count: CalculatorViewModel.Limits.maxInputDigits))
    }

    func testRepeatedEqualsRepeatsLastBinaryOperation() {
        let viewModel = CalculatorViewModel()

        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        enter("2", into: viewModel)
        viewModel.evaluate()
        viewModel.evaluate()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "11")
        XCTAssertEqual(viewModel.expressionDisplay, "9 + 2 =")
        XCTAssertEqual(viewModel.history.count, 3)
        XCTAssertEqual(viewModel.history[0].expression, "9 + 2")
        XCTAssertEqual(viewModel.history[0].result, "11")
        XCTAssertEqual(viewModel.history[1].expression, "7 + 2")
        XCTAssertEqual(viewModel.history[1].result, "9")
        XCTAssertEqual(viewModel.history[2].expression, "5 + 2")
        XCTAssertEqual(viewModel.history[2].result, "7")
    }

    func testParenthesesExpressionEvaluatesWithExpectedPrecedence() {
        let viewModel = CalculatorViewModel()

        viewModel.inputParenthesis("(")
        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.inputParenthesis(")")
        viewModel.setOperator(.multiply)
        enter("4", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "20")
        XCTAssertEqual(viewModel.expressionDisplay, "( 2 + 3 ) × 4 =")
        XCTAssertEqual(viewModel.history.first?.expression, "( 2 + 3 ) × 4")
        XCTAssertEqual(viewModel.history.first?.result, "20")
    }

    func testParenthesesToggleButtonInsertsOpenThenClose() {
        let viewModel = CalculatorViewModel()

        viewModel.inputParentheses()
        enter("8", into: viewModel)
        viewModel.inputParentheses()
        viewModel.setOperator(.add)
        enter("2", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "10")
        XCTAssertEqual(viewModel.history.first?.expression, "( 8 ) + 2")
    }

    func testSquareInsideParenthesesRemainsInExpressionAndEvaluates() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        viewModel.setOperator(.multiply)
        viewModel.inputParenthesis("(")
        enter("9", into: viewModel)
        viewModel.square()

        XCTAssertEqual(viewModel.expressionDisplay, "8 × ( 9²")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "648")
        XCTAssertEqual(viewModel.expressionDisplay, "8 × ( 9² ) =")
        XCTAssertEqual(viewModel.history.first?.expression, "8 × ( sqr(9) )")
        XCTAssertEqual(viewModel.history.first?.displayExpression, "8 × ( 9² )")
        XCTAssertEqual(viewModel.history.first?.result, "648")
    }

    func testSquareRootThenParenthesizedExpressionImplicitlyMultiplies() {
        let viewModel = CalculatorViewModel()

        enter("4", into: viewModel)
        viewModel.squareRoot()
        viewModel.inputParenthesis("(")
        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        enter("2", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "8")
        XCTAssertEqual(viewModel.expressionDisplay, "√(4) × ( 2 + 2 ) =")
        XCTAssertEqual(viewModel.history.first?.expression, "√(4) × ( 2 + 2 )")
        XCTAssertEqual(viewModel.history.first?.result, "8")
    }

    func testReciprocalThenParenthesizedExpressionImplicitlyMultiplies() {
        let viewModel = CalculatorViewModel()

        enter("4", into: viewModel)
        viewModel.reciprocal()
        viewModel.inputParenthesis("(")
        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        enter("2", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "1")
        XCTAssertEqual(viewModel.expressionDisplay, "1/(4) × ( 2 + 2 ) =")
        XCTAssertEqual(viewModel.history.first?.expression, "1/(4) × ( 2 + 2 )")
        XCTAssertEqual(viewModel.history.first?.result, "1")
    }

    func testSquareThenParenthesizedExpressionImplicitlyMultiplies() {
        let viewModel = CalculatorViewModel()

        enter("3", into: viewModel)
        viewModel.square()
        viewModel.inputParenthesis("(")
        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        enter("1", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "27")
        XCTAssertEqual(viewModel.expressionDisplay, "3² × ( 2 + 1 ) =")
        XCTAssertEqual(viewModel.history.first?.expression, "sqr(3) × ( 2 + 1 )")
        XCTAssertEqual(viewModel.history.first?.displayExpression, "3² × ( 2 + 1 )")
        XCTAssertEqual(viewModel.history.first?.result, "27")
    }

    func testNestedParenthesesWithSquareRootEvaluatesWithExpectedPrecedence() {
        let viewModel = CalculatorViewModel()

        viewModel.inputParenthesis("(")
        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.inputParenthesis(")")
        viewModel.inputParenthesis("(")
        enter("4", into: viewModel)
        viewModel.squareRoot()
        viewModel.setOperator(.add)
        enter("1", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "15")
        XCTAssertEqual(viewModel.expressionDisplay, "( 2 + 3 ) × ( √(4) + 1 ) =")
        XCTAssertEqual(viewModel.history.first?.expression, "( 2 + 3 ) × ( √(4) + 1 )")
        XCTAssertEqual(viewModel.history.first?.result, "15")
    }

    func testPercentConvertsCurrentInputToDecimalValue() {
        let viewModel = CalculatorViewModel()

        enter("50", into: viewModel)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "0.5")
        XCTAssertEqual(viewModel.expressionDisplay, "50%")
        XCTAssertFalse(viewModel.isErrorState)
    }

    func testClassicPercentModeTreatsEvaluatedValuesLikeClassicBehavior() {
        let viewModel = CalculatorViewModel()

        enter("50", into: viewModel)
        viewModel.evaluate()
        viewModel.setClassicPercentBehaviorEnabled(true)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "25")
        XCTAssertEqual(viewModel.expressionDisplay, "50%")
        XCTAssertFalse(viewModel.isErrorState)
    }

    func testClassicPercentModeTreatsStandaloneInputLikeCalculator() {
        let viewModel = CalculatorViewModel()

        viewModel.setClassicPercentBehaviorEnabled(true)
        enter("50", into: viewModel)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "0")
        XCTAssertEqual(viewModel.expressionDisplay, "50%")
        XCTAssertFalse(viewModel.isErrorState)
    }

    func testPercentMatchesCalculatorForAddition() {
        let viewModel = CalculatorViewModel()

        enter("10", into: viewModel)
        viewModel.setOperator(.add)
        enter("10", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "11")
        XCTAssertEqual(viewModel.expressionDisplay, "10 + 1 =")
        XCTAssertEqual(viewModel.history.first?.expression, "10 + 1")
        XCTAssertEqual(viewModel.history.first?.result, "11")
    }

    func testPercentMatchesCalculatorForDivision() {
        let viewModel = CalculatorViewModel()

        enter("10", into: viewModel)
        viewModel.setOperator(.divide)
        enter("10", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "100")
        XCTAssertEqual(viewModel.expressionDisplay, "10 ÷ 0.1 =")
        XCTAssertEqual(viewModel.history.first?.expression, "10 ÷ 0.1")
        XCTAssertEqual(viewModel.history.first?.result, "100")
    }

    func testPercentAfterStandalonePercentUsesStandaloneSemantics() {
        let viewModel = CalculatorViewModel()

        enter("5", into: viewModel)
        viewModel.applyPercent()
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.expressionDisplay, "5% + 3%")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "0.08")
        XCTAssertEqual(viewModel.expressionDisplay, "5% + 3% =")
        XCTAssertEqual(viewModel.history.first?.expression, "5% + 3%")
        XCTAssertEqual(viewModel.history.first?.result, "0.08")
    }

    func testAdditionAfterStandalonePercentUsesPercentValueAsLeftOperand() {
        let viewModel = CalculatorViewModel()

        enter("5", into: viewModel)
        viewModel.applyPercent()
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "3.05")
        XCTAssertEqual(viewModel.expressionDisplay, "5% + 3 =")
        XCTAssertEqual(viewModel.history.first?.expression, "5% + 3")
        XCTAssertEqual(viewModel.history.first?.result, "3.05")
    }

    func testSquareRootOfNegativeNumberSetsInvalidInputError() {
        let viewModel = CalculatorViewModel()

        enter("9", into: viewModel)
        viewModel.toggleSign()
        viewModel.squareRoot()

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "Invalid input")
        XCTAssertEqual(viewModel.expressionDisplay, "")
    }

    func testReciprocalOfZeroSetsDivideByZeroError() {
        let viewModel = CalculatorViewModel()

        viewModel.reciprocal()

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "Cannot divide by zero")
    }

    func testMemoryStoreRecallAddSubtractAndClearFlow() {
        let viewModel = CalculatorViewModel()

        enter("12", into: viewModel)
        viewModel.storeMemory()
        XCTAssertEqual(viewModel.memoryValue, 12)
        XCTAssertEqual(viewModel.memoryDisplay, "12")

        viewModel.clearAll()
        enter("3", into: viewModel)
        viewModel.addToMemory()
        XCTAssertEqual(viewModel.memoryValue, 15)
        XCTAssertEqual(viewModel.memoryDisplay, "15")

        viewModel.clearAll()
        enter("5", into: viewModel)
        viewModel.subtractFromMemory()
        XCTAssertEqual(viewModel.memoryValue, 10)
        XCTAssertEqual(viewModel.memoryDisplay, "10")

        viewModel.recallMemory()
        XCTAssertEqual(viewModel.display, "10")

        viewModel.clearMemory()
        XCTAssertNil(viewModel.memoryValue)
        XCTAssertNil(viewModel.memoryDisplay)
        XCTAssertTrue(viewModel.memoryEntries.isEmpty)
    }

    func testHistoryIsCappedAtMaximumEntryCount() {
        let viewModel = CalculatorViewModel()
        let retainedEntryCount = CalculatorViewModel.Limits.maxStoredHistoryEntries
        let totalEvaluations = retainedEntryCount + 10
        let expectedNewestExpression = "\(totalEvaluations) + 1"
        let expectedOldestRetainedExpression = "11 + 1"

        enter("1", into: viewModel)
        viewModel.setOperator(.add)
        enter("1", into: viewModel)

        for _ in 0..<totalEvaluations {
            viewModel.evaluate()
        }

        XCTAssertEqual(viewModel.history.count, retainedEntryCount)
        XCTAssertEqual(viewModel.history.first?.expression, expectedNewestExpression)
        XCTAssertEqual(viewModel.history.last?.expression, expectedOldestRetainedExpression)
    }

    func testMemoryEntriesAreCappedAtMaximumEntryCount() {
        let viewModel = CalculatorViewModel()
        let retainedEntryCount = CalculatorViewModel.Limits.maxStoredMemoryEntries
        let totalStoredValues = retainedEntryCount + 5
        let expectedOldestRetainedValue = Double(totalStoredValues - retainedEntryCount + 1)

        for value in 1...totalStoredValues {
            viewModel.clearAll()
            enter(String(value), into: viewModel)
            viewModel.storeMemory()
        }

        XCTAssertEqual(viewModel.memoryEntries.count, retainedEntryCount)
        XCTAssertEqual(viewModel.memoryEntries.first?.value, Double(totalStoredValues))
        XCTAssertEqual(viewModel.memoryEntries.last?.value, expectedOldestRetainedValue)
    }

    func testUndoDepthIsCappedAtMaximumEntryCount() {
        let viewModel = CalculatorViewModel()

        for value in 0..<(CalculatorViewModel.Limits.maxUndoDepth + 20) {
            viewModel.clearAll()
            viewModel.inputDigit(String((value % 9) + 1))
        }

        XCTAssertEqual(viewModel.undoDepth, CalculatorViewModel.Limits.maxUndoDepth)
        XCTAssertEqual(viewModel.redoDepth, 0)
    }

    func testReuseHistoryEntryRestoresResultAsNewInput() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("7", into: viewModel)
        viewModel.evaluate()
        XCTAssertNotNil(viewModel.history.first)
        let entry = viewModel.history[0]

        viewModel.clearAll()
        viewModel.reuse(entry)

        XCTAssertEqual(viewModel.display, "56")
        XCTAssertEqual(viewModel.expressionDisplay, "8 × 7 =")

        viewModel.inputDigit("2")
        XCTAssertEqual(viewModel.display, "2")
    }

    func testLanguageOverrideReturnsLocalizedSettingsLabel() throws {
        let bundle = try localizedBundle(named: "de")

        languageOverrideBundle = bundle

        XCTAssertEqual(localized("settings.language"), "Sprache")
        XCTAssertEqual(localized("settings.credit.linkText"), "GitHub")
    }

    func testRefreshLocalizationUpdatesActiveErrorMessage() throws {
        let viewModel = CalculatorViewModel()

        enter("1", into: viewModel)
        viewModel.setOperator(.divide)
        enter("0", into: viewModel)
        viewModel.evaluate()
        XCTAssertEqual(viewModel.display, "Cannot divide by zero")

        languageOverrideBundle = try localizedBundle(named: "de")
        viewModel.refreshLocalization()

        XCTAssertEqual(viewModel.display, "Durch Null kann nicht geteilt werden")
    }

    func testLocalizedUsesModuleFallbackWhenLanguageOverrideIsNil() {
        let originalBundle = languageOverrideBundle
        defer { languageOverrideBundle = originalBundle }

        languageOverrideBundle = nil

        let key = "settings.title"
        let moduleValue = Bundle.enterCalcCore.localizedString(forKey: key, value: nil, table: "Localizable")

        XCTAssertNotEqual(moduleValue, key)
        XCTAssertEqual(localized(key), moduleValue)
        XCTAssertNil(languageOverrideBundle)
    }

    func testLocalizedCreditsExistAcrossSupportedBundles() throws {
        let localeCodes = ["Base", "en", "de", "es", "fr", "ja", "zh-Hans"]
        let creditKeys = [
            "settings.credit.part1",
            "settings.credit.linkText",
            "settings.credit.middle"
        ]

        for localeCode in localeCodes {
            let strings = try localizedStrings(named: localeCode)
            for key in creditKeys {
                guard let value = strings[key] as? String else {
                    XCTFail("Missing \(key) in \(localeCode).lproj")
                    continue
                }
                XCTAssertNotNil(value, "Missing \(key) in \(localeCode).lproj")
                XCTAssertNotEqual(value, key, "Missing \(key) in \(localeCode).lproj")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty \(key) in \(localeCode).lproj")
            }
        }

        let englishStrings = try localizedStrings(named: "en")
        let englishCredit = [
            englishStrings["settings.credit.part1"] as? String ?? "",
            englishStrings["settings.credit.linkText"] as? String ?? "",
            englishStrings["settings.credit.middle"] as? String ?? ""
        ].joined()

        XCTAssertTrue(englishCredit.contains("MIT License"))
        XCTAssertTrue(englishCredit.contains("Tipli AI"))
    }

    func testAboutAndCreditStringsStayAlignedAcrossSupportedBundles() throws {
        let localeCodes = ["Base", "en", "de", "es", "fr", "ja", "zh-Hans"]

        for localeCode in localeCodes {
            let strings = try localizedStrings(named: localeCode)

            let aboutLabel = try XCTUnwrap(strings["settings.credits"] as? String, "Missing settings.credits in \(localeCode).lproj")
            XCTAssertFalse(aboutLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty settings.credits in \(localeCode).lproj")

            let versionLabel = try XCTUnwrap(strings["settings.credits.version"] as? String, "Missing settings.credits.version in \(localeCode).lproj")
            XCTAssertTrue(versionLabel.contains("%@"), "settings.credits.version should keep its placeholder in \(localeCode).lproj")

            let aboutWindowTitle = try XCTUnwrap(strings["mac.about.windowTitle"] as? String, "Missing mac.about.windowTitle in \(localeCode).lproj")
            XCTAssertTrue(aboutWindowTitle.contains("%@"), "mac.about.windowTitle should keep its placeholder in \(localeCode).lproj")

            let creditPart1 = try XCTUnwrap(strings["settings.credit.part1"] as? String, "Missing settings.credit.part1 in \(localeCode).lproj")
            XCTAssertTrue(creditPart1.contains("EnterCalc"), "settings.credit.part1 should mention EnterCalc in \(localeCode).lproj")

            let creditLinkText = try XCTUnwrap(strings["settings.credit.linkText"] as? String, "Missing settings.credit.linkText in \(localeCode).lproj")
            XCTAssertEqual(creditLinkText, "GitHub", "settings.credit.linkText should stay consistent in \(localeCode).lproj")
        }
    }

    func testScreenStoreStartsWithOneHomeScreen() {
        let store = CalculatorScreenStore(homeSettings: makeScreenSettings())

        XCTAssertEqual(store.screenCount, 1)
        XCTAssertEqual(store.activeIndex, 0)
        XCTAssertTrue(store.activeScreen.isHomeScreen)
        XCTAssertFalse(store.canCloseActiveScreen)
        XCTAssertTrue(store.canCreateScreen)
    }

    func testScreenInsertionOccursImmediatelyRightOfActiveScreen() {
        let homeSettings = makeScreenSettings()
        let store = CalculatorScreenStore(homeSettings: homeSettings)

        XCTAssertTrue(store.insertScreenAfterActive(homeSettings: homeSettings))
        let firstInsertedID = store.activeScreen.id

        XCTAssertTrue(store.insertScreenAfterActive(homeSettings: homeSettings))
        let secondInsertedID = store.activeScreen.id

        XCTAssertTrue(store.activateScreen(at: 1))
        XCTAssertTrue(store.insertScreenAfterActive(homeSettings: homeSettings))
        let middleInsertedID = store.activeScreen.id

        XCTAssertEqual(store.screenCount, 4)
        XCTAssertEqual(store.activeIndex, 2)
        XCTAssertEqual(store.screens.map(\.id), [store.homeScreen.id, firstInsertedID, middleInsertedID, secondInsertedID])
    }

    func testClosingSubScreenSelectsImmediateLeftNeighbor() {
        let homeSettings = makeScreenSettings()
        let store = CalculatorScreenStore(homeSettings: homeSettings)

        XCTAssertTrue(store.insertScreenAfterActive(homeSettings: homeSettings))
        let leftNeighborID = store.activeScreen.id
        XCTAssertTrue(store.insertScreenAfterActive(homeSettings: homeSettings))

        XCTAssertTrue(store.closeActiveScreen())
        XCTAssertEqual(store.screenCount, 2)
        XCTAssertEqual(store.activeIndex, 1)
        XCTAssertEqual(store.activeScreen.id, leftNeighborID)
        XCTAssertFalse(store.activeScreen.isHomeScreen)
    }

    func testHomeScreenCannotBeClosedAndScreenCountCapsAtFive() {
        let homeSettings = makeScreenSettings()
        let store = CalculatorScreenStore(homeSettings: homeSettings)

        XCTAssertFalse(store.closeActiveScreen())

        for _ in 0..<4 {
            XCTAssertTrue(store.insertScreenAfterActive(homeSettings: homeSettings))
        }

        XCTAssertEqual(store.screenCount, CalculatorScreenStore.maxScreenCount)
        XCTAssertFalse(store.canCreateScreen)
        XCTAssertFalse(store.insertScreenAfterActive(homeSettings: homeSettings))
    }

    func testNewScreenInheritsHomeSettingsNotCurrentSubScreenSettings() {
        let homeSettings = makeScreenSettings(themeRawValue: "light", languageCode: "en")
        let store = CalculatorScreenStore(homeSettings: homeSettings)

        XCTAssertTrue(store.insertScreenAfterActive(homeSettings: homeSettings))

        let subScreen = store.activeScreen
        subScreen.updateSettings {
            $0.themeRawValue = "dark"
            $0.languageCode = "de"
            $0.usesScientificNotation = false
            $0.numberFormatStyleRawValue = NumberFormatStyle.european.rawValue
            $0.usesClassicPercentBehavior = true
        }

        XCTAssertTrue(store.insertScreenAfterActive(homeSettings: homeSettings))

        XCTAssertEqual(store.activeScreen.settings, homeSettings)
        XCTAssertNotEqual(store.activeScreen.settings, subScreen.settings)
    }

    func testNewScreenUsesUpdatedHomeSettingsWhileExistingSubScreenKeepsItsOwnSettings() {
        let initialHomeSettings = makeScreenSettings(themeRawValue: "light", languageCode: defaultLocalizationSelectionCode)
        let store = CalculatorScreenStore(homeSettings: initialHomeSettings)

        XCTAssertTrue(store.insertScreenAfterActive(homeSettings: initialHomeSettings))
        let existingSubScreen = store.activeScreen
        existingSubScreen.updateSettings {
            $0.languageCode = "fr"
            $0.themeRawValue = "dark"
        }

        let updatedHomeSettings = makeScreenSettings(themeRawValue: "system", languageCode: "de")
        store.syncHomeScreenSettings(updatedHomeSettings)

        XCTAssertEqual(store.homeScreen.settings, updatedHomeSettings)
        XCTAssertEqual(existingSubScreen.settings.languageCode, "fr")
        XCTAssertEqual(existingSubScreen.settings.themeRawValue, "dark")

        XCTAssertTrue(store.insertScreenAfterActive(homeSettings: updatedHomeSettings))
        XCTAssertEqual(store.activeScreen.settings, updatedHomeSettings)
        XCTAssertEqual(existingSubScreen.settings.languageCode, "fr")
    }

    func testPersistedSettingsAffectNewlyLoadedSettingsWithoutMutatingExistingInMemorySettings() {
        let suiteName = "enterCalc.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated user defaults suite")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let existingLoadedSettings = CalculatorScreenSettingsPersistence.load(from: defaults)
        let updatedDefaults = makeScreenSettings(themeRawValue: "dark", languageCode: "de")

        CalculatorScreenSettingsPersistence.persist(updatedDefaults, to: defaults)
        let reloadedSettings = CalculatorScreenSettingsPersistence.load(from: defaults)

        XCTAssertEqual(existingLoadedSettings.languageCode, defaultLocalizationSelectionCode)
        XCTAssertEqual(reloadedSettings, updatedDefaults)
    }

    func testScreensKeepIndependentCalculatorState() {
        let homeSettings = makeScreenSettings()
        let store = CalculatorScreenStore(homeSettings: homeSettings)
        let homeViewModel = store.homeScreen.viewModel

        enter("12", into: homeViewModel)
        homeViewModel.setOperator(.add)
        enter("3", into: homeViewModel)
        homeViewModel.evaluate()
        homeViewModel.storeMemory()

        XCTAssertTrue(store.insertScreenAfterActive(homeSettings: homeSettings))
        let secondViewModel = store.activeScreen.viewModel

        enter("7", into: secondViewModel)
        secondViewModel.storeMemory()

        XCTAssertEqual(homeViewModel.display, "15")
        XCTAssertEqual(homeViewModel.history.count, 1)
        XCTAssertEqual(homeViewModel.memoryValue, 15)
        XCTAssertTrue(secondViewModel.history.isEmpty)
        XCTAssertEqual(secondViewModel.memoryValue, 7)
        XCTAssertEqual(secondViewModel.display, "7")
    }

    func testScreenLocalizationKeysExistAcrossSupportedBundles() throws {
        let localeCodes = ["Base", "en", "de", "es", "fr", "ja", "zh-Hans"]
        let screenKeys = [
            "settings.screen.title",
            "settings.appearance.screenLabel",
            "screen.new",
            "screen.close",
            "screen.pageStatus"
        ]

        for localeCode in localeCodes {
            let strings = try localizedStrings(named: localeCode)
            for key in screenKeys {
                guard let value = strings[key] as? String else {
                    XCTFail("Missing \(key) in \(localeCode).lproj")
                    continue
                }
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty \(key) in \(localeCode).lproj")
                XCTAssertNotEqual(value, key, "Untranslated \(key) in \(localeCode).lproj")
            }
        }
    }

    func testResolvedLocalizationCodeMapsBaseLanguageToSupportedScriptLocalization() {
        let resolvedCode = resolvedLocalizationCode(for: "zh", in: Bundle.enterCalcCore, preferredLanguages: ["zh"])

        XCTAssertEqual(resolvedCode.lowercased(), "zh-hans")
        XCTAssertNotNil(localizationBundle(for: "zh", in: Bundle.enterCalcCore))
    }

    func testResolvedLocalizationCodeFallsBackToEnglishForUnknownLanguage() {
        XCTAssertEqual(
            resolvedLocalizationCode(for: "zz-ZZ", in: Bundle.enterCalcCore, preferredLanguages: ["zz-ZZ"]),
            "en"
        )
    }

    func testResolvedLocalizationCodeUsesPreferredLanguageForDefaultSelection() {
        XCTAssertEqual(
            resolvedLocalizationCode(for: defaultLocalizationSelectionCode, in: Bundle.enterCalcCore, preferredLanguages: ["de-DE"]),
            "de"
        )
    }

    func testLicenseFileContainsRequiredNotices() throws {
        let licenseURL = try XCTUnwrap(findLicenseURL(), "Unable to locate LICENSE in bundled resources or repository checkout")
        let licenseText = try String(contentsOf: licenseURL, encoding: .utf8)

        XCTAssertTrue(licenseText.contains("MIT License"))
        XCTAssertTrue(licenseText.contains("Tipli AI"))
    }

    #if canImport(AppKit)
    func testCopyToPasteboardWritesUngroupedValue() {
        let viewModel = CalculatorViewModel()

        enter("1234", into: viewModel)
        viewModel.copyToPasteboard()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "1234")
    }

    func testCopyToPasteboardUsesLocalizedDecimalSeparatorForFrenchStyle() {
        let viewModel = CalculatorViewModel(numberFormatStyle: .french)

        pasteString("8,333", into: viewModel)
        viewModel.copyToPasteboard()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "8,333")
    }

    func testCopyToPasteboardCopiesRoundedValueWhenRoundingIsEnabled() {
        let viewModel = CalculatorViewModel()

        pasteString("9.32227", into: viewModel)
        viewModel.beginResultRounding(defaultPrecision: 4)
        XCTAssertEqual(viewModel.display, "9.3223")

        viewModel.copyToPasteboard()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "9.3223")
    }

    func testCommitResultRoundingDoesNotAppendHistoryForIncompletePendingOperation() {
        let viewModel = CalculatorViewModel()

        enter("12", into: viewModel)
        viewModel.setOperator(.add)
        viewModel.beginResultRounding(defaultPrecision: 4)
        viewModel.commitResultRoundingInteraction()

        XCTAssertTrue(viewModel.history.isEmpty)
    }

    func testOpenThenRemoveResultRoundingDoesNotAppendHistory() {
        let viewModel = CalculatorViewModel()

        pasteString("9.32227", into: viewModel)
        viewModel.beginResultRounding(defaultPrecision: 4)
        viewModel.removeResultRounding()
        viewModel.commitResultRoundingInteraction()

        XCTAssertTrue(viewModel.history.isEmpty)
        XCTAssertEqual(viewModel.display, "9.32227")
    }

    func testExactRoundingUsesEqualsAndPreservesZeroPadding() throws {
        let viewModel = CalculatorViewModel()

        pasteString("5", into: viewModel)
        viewModel.beginResultRounding(defaultPrecision: 3)

        XCTAssertEqual(viewModel.display, "5.000")
        XCTAssertEqual(viewModel.expressionDisplay, "round(5, 3) = 5.000")

        viewModel.commitResultRoundingInteraction()

        let entry = try XCTUnwrap(viewModel.history.first)
        XCTAssertEqual(entry.expression, "round(5, 3)")
        XCTAssertEqual(entry.result, "5.000")
        XCTAssertEqual(entry.displayResult, "5.000")

        viewModel.copyOperationToPasteboard(entry)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "round(5, 3) = 5.000")
    }

    func testCopyOperationThenPasteReplaysTheOperation() {
        let sourceViewModel = CalculatorViewModel()
        enter("12", into: sourceViewModel)
        sourceViewModel.setOperator(.add)
        enter("3", into: sourceViewModel)
        sourceViewModel.evaluate()
        sourceViewModel.copyOperationToPasteboard()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "12 + 3 = 15")

        let pastedViewModel = CalculatorViewModel()
        pastedViewModel.pasteFromPasteboard()

        XCTAssertEqual(pastedViewModel.display, "15")
        XCTAssertTrue(pastedViewModel.history.isEmpty)
        XCTAssertFalse(pastedViewModel.isErrorState)
    }

    func testPasteFromPasteboardNormalizesFormattedNumericContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("$1,234.50", forType: .string)

        let viewModel = CalculatorViewModel()
        viewModel.pasteFromPasteboard()

        XCTAssertEqual(viewModel.display, "1,234.50")
        XCTAssertFalse(viewModel.isErrorState)
    }

    func testPasteFromPasteboardConvertsFrenchNumberToWesternActiveFormat() {
        let viewModel = CalculatorViewModel(numberFormatStyle: .western)

        pasteString("1 000,00", into: viewModel)

        XCTAssertEqual(viewModel.display, "1,000.00")
        XCTAssertFalse(viewModel.isErrorState)
    }

    func testPasteFromPasteboardConvertsWesternNumberToFrenchActiveFormat() {
        let viewModel = CalculatorViewModel(numberFormatStyle: .french)

        pasteString("1,000.00", into: viewModel)

        XCTAssertEqual(viewModel.display, "1 000,00")
        XCTAssertFalse(viewModel.isErrorState)
    }

    func testPasteFromPasteboardReplacesPendingOperandWithoutClearingOperation() {
        let viewModel = CalculatorViewModel()

        enter("12", into: viewModel)
        viewModel.setOperator(.add)
        pasteString("3", into: viewModel)

        XCTAssertEqual(viewModel.expressionDisplay, "12 + 3")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "15")
        XCTAssertEqual(viewModel.history.first?.expression, "12 + 3")
        XCTAssertEqual(viewModel.history.first?.result, "15")
    }

    func testPasteFromPasteboardRejectsOversizedNumericInput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(repeating: "9", count: CalculatorViewModel.Limits.maxPasteCharacters + 1), forType: .string)

        let viewModel = CalculatorViewModel()
        viewModel.pasteFromPasteboard()

        XCTAssertEqual(viewModel.display, "0")
        XCTAssertTrue(viewModel.history.isEmpty)
        XCTAssertTrue(viewModel.memoryEntries.isEmpty)
    }
    #endif

    private func enter(_ value: String, into viewModel: CalculatorViewModel) {
        for character in value {
            if character == "." {
                viewModel.inputDecimal()
            } else {
                viewModel.inputDigit(String(character))
            }
        }
    }

    private func makeScreenSettings(
        themeRawValue: String = "system",
        languageCode: String = "en",
        usesScientificNotation: Bool = true,
        numberFormatStyleRawValue: String = NumberFormatStyle.western.rawValue,
        usesClassicPercentBehavior: Bool = false
    ) -> CalculatorScreenSettings {
        CalculatorScreenSettings(
            themeRawValue: themeRawValue,
            languageCode: languageCode,
            usesScientificNotation: usesScientificNotation,
            numberFormatStyleRawValue: numberFormatStyleRawValue,
            usesClassicPercentBehavior: usesClassicPercentBehavior
        )
    }

    private func localizedBundle(named localeCode: String) throws -> Bundle {
        if let path = Bundle.enterCalcCore.path(forResource: localeCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        let normalizedLocale = localeCode.replacingOccurrences(of: "-", with: "_")
        let resourceRoot = try XCTUnwrap(Bundle.enterCalcCore.resourceURL)
        let lprojURLs = try FileManager.default.contentsOfDirectory(
            at: resourceRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "lproj" }

        guard let bundleURL = lprojURLs.first(where: {
            $0.deletingPathExtension()
                .lastPathComponent
                .replacingOccurrences(of: "-", with: "_")
                .caseInsensitiveCompare(normalizedLocale) == .orderedSame
        }),
        let bundle = Bundle(path: bundleURL.path) else {
            throw XCTSkip("Missing localization bundle: \(localeCode).lproj")
        }
        return bundle
    }

    private func localizedStrings(named localeCode: String) throws -> NSDictionary {
        let bundle = try localizedBundle(named: localeCode)
        guard let stringsURL = bundle.url(forResource: "Localizable", withExtension: "strings") else {
            throw NSError(
                domain: "CalculatorViewModelTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to locate Localizable.strings in \(localeCode).lproj bundle"]
            )
        }

        guard let strings = NSDictionary(contentsOf: stringsURL) else {
            throw NSError(
                domain: "CalculatorViewModelTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to load localized strings at \(stringsURL.path)"]
            )
        }

        return strings
    }

    private func findLicenseURL() -> URL? {
        let bundleCandidates = [Bundle.main, Bundle(for: Self.self), Bundle.enterCalcCore]
        for bundle in bundleCandidates {
            if let url = bundle.url(forResource: "LICENSE", withExtension: nil) {
                return url
            }

            if let resourceURL = bundle.resourceURL {
                let candidate = resourceURL.appendingPathComponent("LICENSE")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
        let packageRoot = sourceURL.deletingLastPathComponent().deletingLastPathComponent()
        let packageLicenseURL = packageRoot.appendingPathComponent("LICENSE")
        if FileManager.default.fileExists(atPath: packageLicenseURL.path) {
            return packageLicenseURL
        }

        let repositoryRoot = packageRoot.deletingLastPathComponent()
        let repoLicenseURL = repositoryRoot.appendingPathComponent("LICENSE")
        if FileManager.default.fileExists(atPath: repoLicenseURL.path) {
            return repoLicenseURL
        }

        return nil
    }

    // MARK: - Out Of Range

    func testRepeatedSquaringOverflowSetsErrorState() {
        let viewModel = CalculatorViewModel()

        // 8^2^2^2^2^2 — each square() call squares the current display value.
        // After enough iterations the number exceeds the representable range and must
        // enter an overflow error state instead of silently showing 0.
        enter("8", into: viewModel)
        viewModel.square() // 64
        viewModel.square() // 4 096
        viewModel.square() // 16 777 216
        viewModel.square() // 281 474 976 710 656
        viewModel.square() // ≈7.9e28 — still representable
        viewModel.square() // ≈6.3e57 — overflows Decimal range

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "Out of range")
        XCTAssertEqual(viewModel.expressionDisplay, "")
    }

    func testOverflowLocalizedInAllSupportedLanguages() throws {
        let viewModel = CalculatorViewModel()

        try withLanguageOverrides { code in
            enter("8", into: viewModel)
            for _ in 0..<6 { viewModel.square() }

            XCTAssertTrue(viewModel.isErrorState, "Expected out-of-range error state for language: \(code)")
            let bundle = try localizedBundle(named: code)
            let expected = bundle.localizedString(forKey: "error.outOfRange", value: nil, table: "Localizable")
            XCTAssertFalse(expected.isEmpty, "Missing error.outOfRange translation for: \(code)")
            XCTAssertEqual(viewModel.display, expected, "Wrong display for language: \(code)")

            viewModel.clearAll()
        }
    }

    func testOverflowClearsCorrectly() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        for _ in 0..<6 { viewModel.square() }
        XCTAssertTrue(viewModel.isErrorState)

        viewModel.clearAll()

        XCTAssertFalse(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "0")
    }

    func testMultiplyOverflowSetsErrorState() {
        let viewModel = CalculatorViewModel()

        // Get to ≈7.9e28 via five squarings of 8 (stays within Decimal range),
        // then multiply that value by itself — the product ≈6.3e57 overflows.
        enter("8", into: viewModel)
        for _ in 0..<5 { viewModel.square() }   // display: ≈7.9e28, no error yet
        XCTAssertFalse(viewModel.isErrorState, "Pre-condition: value should be valid before multiply")

        viewModel.setOperator(.multiply)
        viewModel.evaluate()                      // repeats: ≈7.9e28 × ≈7.9e28 → overflow

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "Out of range")
    }

    func testOverflowKeepsOperationRowEmptyAndOperationCopyUnavailable() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        for _ in 0..<6 { viewModel.square() }

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertFalse(viewModel.hasOperationToCopy)
    }

    func testRepeatedEqualsOverflowSetsErrorInsteadOfZero() {
        let viewModel = CalculatorViewModel()

        enter("999999999999999", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("999999999999999", into: viewModel)
        viewModel.evaluate()

        XCTAssertFalse(viewModel.isErrorState)

        viewModel.evaluate()

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "Out of range")
        XCTAssertEqual(viewModel.expressionDisplay, "")
    }

    func testOverflowDuringPendingOperatorResolutionDoesNotLeaveOperatorPreview() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        for _ in 0..<5 { viewModel.square() }
        viewModel.setOperator(.multiply)
        enter("2000", into: viewModel)

        viewModel.setOperator(.add)

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "Out of range")
        XCTAssertEqual(viewModel.expressionDisplay, "")
    }

    func testOverflowUndoRedoRoundTripsSafely() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        for _ in 0..<6 { viewModel.square() }
        XCTAssertTrue(viewModel.isErrorState)

        for _ in 0..<10 {
            viewModel.undo()
            XCTAssertFalse(viewModel.isErrorState)
            XCTAssertNotEqual(viewModel.display, "0")

            viewModel.redo()
            XCTAssertTrue(viewModel.isErrorState)
            XCTAssertEqual(viewModel.display, "Out of range")
            XCTAssertEqual(viewModel.expressionDisplay, "")
        }

        XCTAssertLessThanOrEqual(viewModel.undoDepth, CalculatorViewModel.Limits.maxUndoDepth)
        XCTAssertLessThanOrEqual(viewModel.redoDepth, CalculatorViewModel.Limits.maxRedoDepth)
    }

    func testClearingAfterOverflowResetsAndAllowsNormalCalculation() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        for _ in 0..<6 { viewModel.square() }
        XCTAssertTrue(viewModel.isErrorState)

        viewModel.clearAll()
        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.evaluate()

        XCTAssertFalse(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "5")
        XCTAssertEqual(viewModel.expressionDisplay, "2 + 3 =")
    }

    func testHistoryPayloadsRemainBoundedUnderLargeInputStress() {
        let viewModel = CalculatorViewModel()

        for _ in 0..<(CalculatorViewModel.Limits.maxStoredHistoryEntries + 20) {
            enter("9999999999999999", into: viewModel)
            viewModel.setOperator(.add)
            enter("1", into: viewModel)
            viewModel.evaluate()
            viewModel.clearAll()
        }

        XCTAssertEqual(viewModel.history.count, CalculatorViewModel.Limits.maxStoredHistoryEntries)
        for entry in viewModel.history {
            XCTAssertLessThanOrEqual(entry.expression.count, CalculatorViewModel.Limits.maxHistoryExpressionCharacters)
            XCTAssertLessThanOrEqual(entry.result.count, CalculatorViewModel.Limits.maxHistoryResultCharacters)
        }
    }

    func testStressLargePasteCalculateUndoRedoCopyHistoryAndClearFlow() {
        let viewModel = CalculatorViewModel()
        let largeMalformed = String(repeating: "9", count: CalculatorViewModel.Limits.maxPasteCharacters - 5)

        for _ in 0..<30 {
            pasteString("9.999999999999999e+15", into: viewModel)
            viewModel.setOperator(.multiply)
            pasteString("9.999999999999999e+15", into: viewModel)
            viewModel.evaluate()

            viewModel.copyToPasteboard()
            XCTAssertNotNil(clipboardString())

            pasteString("Out of range", into: viewModel)
            pasteString(largeMalformed, into: viewModel)

            _ = viewModel.history.first
            _ = viewModel.history.count

            viewModel.undo()
            viewModel.redo()
            viewModel.clearAll()
        }

        XCTAssertLessThanOrEqual(viewModel.history.count, CalculatorViewModel.Limits.maxStoredHistoryEntries)
        XCTAssertLessThanOrEqual(viewModel.undoDepth, CalculatorViewModel.Limits.maxUndoDepth)
        XCTAssertLessThanOrEqual(viewModel.redoDepth, CalculatorViewModel.Limits.maxRedoDepth)
        XCTAssertEqual(viewModel.display, "0")
    }

    func testPastingOutOfRangeTextLeavesOutOfRangeStateStable() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        for _ in 0..<6 { viewModel.square() }
        XCTAssertTrue(viewModel.isErrorState)

        pasteString("Out of range", into: viewModel)

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "Out of range")
        XCTAssertEqual(viewModel.expressionDisplay, "")
    }

    func testCopyOverflowWritesOverflowTextOnly() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        for _ in 0..<6 { viewModel.square() }

        viewModel.copyToPasteboard()

        XCTAssertEqual(clipboardString(), "Out of range")
    }

    func testRepeatedDivisionUnderflowSetsOutOfRangeError() {
        let viewModel = CalculatorViewModel()

        enter("1", into: viewModel)
        for _ in 0..<140 {
            viewModel.setOperator(.divide)
            enter("10", into: viewModel)
            viewModel.evaluate()
            if viewModel.isErrorState { break }
        }

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "Out of range")
        XCTAssertEqual(viewModel.expressionDisplay, "")
    }

    func testSquareRootChainAtLimitStillComputes() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        for _ in 0..<CalculatorViewModel.Limits.maxConsecutiveSquareOrRootDepth {
            viewModel.squareRoot()
        }

        XCTAssertFalse(viewModel.isErrorState)
    }

    func testSquareRootChainBeyondLimitSetsOutOfRange() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        for _ in 0..<(CalculatorViewModel.Limits.maxConsecutiveSquareOrRootDepth + 1) {
            viewModel.squareRoot()
            if viewModel.isErrorState { break }
        }

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "Out of range")
        XCTAssertEqual(viewModel.expressionDisplay, "")
    }

    func testSquareChainBeyondLimitSetsOutOfRangeEvenWhenValueStaysRepresentable() {
        let viewModel = CalculatorViewModel()

        enter("1", into: viewModel)
        for _ in 0..<(CalculatorViewModel.Limits.maxConsecutiveSquareOrRootDepth + 1) {
            viewModel.square()
            if viewModel.isErrorState { break }
        }

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "Out of range")
        XCTAssertEqual(viewModel.expressionDisplay, "")
    }

    func testScientificNotationPasteBeyondRangeIsIgnoredWithoutCorruptingState() {
        let viewModel = CalculatorViewModel()
        enter("42", into: viewModel)

        pasteString("1e999999", into: viewModel)

        XCTAssertFalse(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "42")
    }
}
