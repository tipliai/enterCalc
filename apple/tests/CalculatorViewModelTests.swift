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
        let expectedRoundedCopiedOperation: String
        let expectedStoredRoundedExpression: String
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
                expectedRoundedDisplay: "3",
                expectedRoundedOperation: "=round(3.005, 1) ≈",
                expectedRoundedCopiedOperation: "=round(3.005,1)",
                expectedStoredRoundedExpression: "round(3.005, 2) ≈",
                expectedRoundedCopyResult: "3"
            ),
            StyleFixture(
                style: .european,
                firstOperand: "2,333",
                secondOperand: "1,555",
                expectedExpressionDisplay: "2,333 + 1,555 =",
                expectedDisplay: "3,888",
                roundingInput: "3,005",
                roundingPrecision: 2,
                expectedRoundedDisplay: "3",
                expectedRoundedOperation: "=round(3,005; 1) ≈",
                expectedRoundedCopiedOperation: "=round(3,005;1)",
                expectedStoredRoundedExpression: "round(3,005; 2) ≈",
                expectedRoundedCopyResult: "3"
            ),
            StyleFixture(
                style: .french,
                firstOperand: "2,333",
                secondOperand: "1,555",
                expectedExpressionDisplay: "2,333 + 1,555 =",
                expectedDisplay: "3,888",
                roundingInput: "3,005",
                roundingPrecision: 2,
                expectedRoundedDisplay: "3",
                expectedRoundedOperation: "=round(3,005; 1) ≈",
                expectedRoundedCopiedOperation: "=round(3,005;1)",
                expectedStoredRoundedExpression: "round(3,005; 2) ≈",
                expectedRoundedCopyResult: "3"
            ),
            StyleFixture(
                style: .swiss,
                firstOperand: "1'234.5",
                secondOperand: "2'000.1",
                expectedExpressionDisplay: "1'234.5 + 2'000.1 =",
                expectedDisplay: "3'234.6",
                roundingInput: "3.005",
                roundingPrecision: 2,
                expectedRoundedDisplay: "3",
                expectedRoundedOperation: "=round(3.005, 1) ≈",
                expectedRoundedCopiedOperation: "=round(3.005,1)",
                expectedStoredRoundedExpression: "round(3.005, 2) ≈",
                expectedRoundedCopyResult: "3"
            ),
            StyleFixture(
                style: .indian,
                firstOperand: "12,34,567.89",
                secondOperand: "1.11",
                expectedExpressionDisplay: "12,34,567.89 + 1.11 =",
                expectedDisplay: "12,34,569",
                roundingInput: "12,34,567.8912",
                roundingPrecision: 3,
                expectedRoundedDisplay: "12,34,567.9",
                expectedRoundedOperation: "=round(1234567.8912, 1) ≈",
                expectedRoundedCopiedOperation: "=round(1234567.8912,1)",
                expectedStoredRoundedExpression: "round(12,34,567.8912, 3) ≈",
                expectedRoundedCopyResult: "12,34,567.9"
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

    func testThreeTenthsAdditionRoundsLikeANormalCalculatorDisplay() {
        let viewModel = CalculatorViewModel()

        enter("0.1", into: viewModel)
        viewModel.setOperator(.add)
        enter("0.1", into: viewModel)
        viewModel.setOperator(.add)
        enter("0.1", into: viewModel)
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
                viewModel.beginResultRounding()
                viewModel.setResultRoundingPrecision(fixture.roundingPrecision)

                XCTAssertEqual(viewModel.display, fixture.expectedRoundedDisplay)
                XCTAssertEqual(viewModel.expressionDisplay, fixture.expectedRoundedOperation)

                viewModel.copyOperationToPasteboard()
                XCTAssertEqual(clipboardString(), fixture.expectedRoundedCopiedOperation)

                viewModel.commitResultRoundingInteraction()

                let savedEntry = try XCTUnwrap(viewModel.history.first)
                XCTAssertEqual(savedEntry.expression, fixture.expectedStoredRoundedExpression)
                XCTAssertEqual(savedEntry.displayExpression, fixture.expectedRoundedOperation)
                XCTAssertEqual(savedEntry.result, fixture.expectedRoundedDisplay)
                XCTAssertEqual(savedEntry.displayResult, fixture.expectedRoundedDisplay)

                viewModel.copyResultToPasteboard(savedEntry)
                XCTAssertEqual(clipboardString(), fixture.expectedRoundedCopyResult)

                viewModel.copyOperationToPasteboard(savedEntry)
                XCTAssertEqual(clipboardString(), fixture.expectedRoundedCopiedOperation)

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
        XCTAssertEqual(clipboardString(), "1 240,17")

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

    func testZeroDividedByZeroSetsLocalizedErrorState() {
        let viewModel = CalculatorViewModel()

        enter("0", into: viewModel)
        viewModel.setOperator(.divide)
        enter("0", into: viewModel)
        viewModel.evaluate()

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "Cannot divide by zero")
        XCTAssertEqual(viewModel.expressionDisplay, "")
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

    func testRepeatedEqualsAfterEvaluateDoesNotReplayLastOperation() {
        let viewModel = CalculatorViewModel()

        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        enter("2", into: viewModel)
        viewModel.evaluate()
        viewModel.evaluate()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "7")
        XCTAssertEqual(viewModel.expressionDisplay, "5 + 2 =")
        XCTAssertEqual(viewModel.history.count, 1)
        XCTAssertEqual(viewModel.history[0].expression, "5 + 2")
        XCTAssertEqual(viewModel.history[0].result, "7")
    }

    func testChainedMultiplicationKeepsFullExpressionDisplayOnEvaluate() {
        let viewModel = CalculatorViewModel()

        enter("2", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("2", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("2", into: viewModel)

        XCTAssertEqual(viewModel.expressionDisplay, "2 × 2 × 2")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "8")
        XCTAssertEqual(viewModel.expressionDisplay, "2 × 2 × 2 =")
        XCTAssertEqual(viewModel.history.first?.expression, "2 × 2 × 2")
        XCTAssertEqual(viewModel.history.first?.result, "8")
    }

    func testPressingSameOperatorTwiceWithoutRightOperandIsNoOp() {
        let viewModel = CalculatorViewModel()

        enter("6", into: viewModel)
        viewModel.setOperator(.add)

        XCTAssertEqual(viewModel.expressionDisplay, "6 +")

        viewModel.setOperator(.add)

        XCTAssertEqual(viewModel.display, "6")
        XCTAssertEqual(viewModel.expressionDisplay, "6 +")

        enter("6", into: viewModel)
        viewModel.setOperator(.add)
        enter("6", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "18")
        XCTAssertEqual(viewModel.expressionDisplay, "6 + 6 + 6 =")
        XCTAssertEqual(viewModel.history.first?.expression, "6 + 6 + 6")
        XCTAssertEqual(viewModel.history.first?.result, "18")
    }

    func testEvaluateAfterTrailingOperatorKeepsStandaloneUnaryAndPercentResult() {
        typealias UnaryFixture = (
            name: String,
            input: String,
            apply: (CalculatorViewModel) -> Void,
            expectedDisplayExpression: String,
            expectedHistoryExpression: String,
            expectedResult: String
        )
        let fixtures: [UnaryFixture] = [
            ("square root", "9", { $0.squareRoot() }, "√(9)", "√(9)", "3"),
            ("square", "9", { $0.square() }, "9²", "sqr(9)", "81"),
            ("reciprocal", "4", { $0.reciprocal() }, "1/(4)", "1/(4)", "0.25"),
            ("percent", "50", { $0.applyPercent() }, "50%", "50%", "0.5")
        ]
        let trailingOperators: [(BinaryOperator, String)] = [
            (.add, "+"), (.subtract, "−"), (.multiply, "×"), (.divide, "÷")
        ]

        for fixture in fixtures {
            for (op, opSymbol) in trailingOperators {
                let viewModel = CalculatorViewModel()
                enter(fixture.input, into: viewModel)
                fixture.apply(viewModel)
                viewModel.setOperator(op)
                viewModel.evaluate()

                let label = "\(fixture.name) trailing \(opSymbol)"
                XCTAssertEqual(viewModel.display, fixture.expectedResult, "Unexpected result for \(label)")
                XCTAssertEqual(viewModel.expressionDisplay, "\(fixture.expectedDisplayExpression) =", "Unexpected expression for \(label)")
                XCTAssertEqual(viewModel.history.count, 1, "Unexpected history count for \(label)")
                XCTAssertEqual(viewModel.history.first?.expression, fixture.expectedHistoryExpression, "Unexpected history expression for \(label)")
                XCTAssertEqual(viewModel.history.first?.result, fixture.expectedResult, "Unexpected history result for \(label)")
            }
        }
    }

    func testEvaluateTrailingOperatorInChainUsesComputedAccumulatorAndStoresHistory() {
        let viewModel = CalculatorViewModel()

        enter("1", into: viewModel)
        viewModel.setOperator(.add)
        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.setOperator(.add)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "6")
        XCTAssertEqual(viewModel.expressionDisplay, "1 + 2 + 3 =")
        XCTAssertEqual(viewModel.history.count, 1)
        XCTAssertEqual(viewModel.history.first?.expression, "1 + 2 + 3")
        XCTAssertEqual(viewModel.history.first?.result, "6")
    }

    func testMixedPrecedenceSimpleChainUsesNestedPostEqualsDisplayAndPrecedenceOnEvaluate() {
        let viewModel = CalculatorViewModel()

        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        enter("2", into: viewModel)
        viewModel.setOperator(.multiply)

        XCTAssertEqual(viewModel.display, "2")
        XCTAssertEqual(viewModel.expressionDisplay, "2 + 2 ×")

        enter("2", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "6")
        XCTAssertEqual(viewModel.expressionDisplay, "2 + (2 × 2) =")
        XCTAssertEqual(viewModel.history.first?.expression, "2 + 2 × 2")
        XCTAssertEqual(viewModel.history.first?.result, "6")
    }

    func testMixedPrecedenceWithParenthesizedSegmentUsesNestedPostEqualsDisplay() {
        let viewModel = CalculatorViewModel()

        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        enter("6", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        viewModel.inputParenthesis("(")
        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        enter("665", into: viewModel)
        viewModel.inputParenthesis(")")
        viewModel.setOperator(.subtract)
        enter("5", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "700")
        XCTAssertEqual(viewModel.expressionDisplay, "5 + (6 × 5) + 5 + 665 − 5 =")
        XCTAssertEqual(viewModel.history.first?.expression, "5 + 6 × 5 + ( 5 + 665 ) − 5")
        XCTAssertEqual(viewModel.history.first?.result, "700")
    }

    func testMixedChainDoesNotComputeDisplayUntilEvaluate() {
        let viewModel = CalculatorViewModel()

        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        enter("6", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("5", into: viewModel)
        viewModel.setOperator(.add)

        XCTAssertEqual(viewModel.display, "5")
        XCTAssertEqual(viewModel.expressionDisplay, "5 + 6 × 5 +")
    }

    func testSwitchingFromPlusToMinusWithPendingOperandKeepsFullExpression() {
        let viewModel = CalculatorViewModel()

        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        enter("2", into: viewModel)
        viewModel.setOperator(.subtract)

        XCTAssertEqual(viewModel.expressionDisplay, "2 + 2 −")

        enter("1", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "3")
        XCTAssertEqual(viewModel.expressionDisplay, "2 + 2 − 1 =")
        XCTAssertEqual(viewModel.history.first?.expression, "2 + 2 − 1")
        XCTAssertEqual(viewModel.history.first?.result, "3")
    }

    func testSwitchingPendingOperatorWithoutNewOperandPreservesChain() {
        let viewModel = CalculatorViewModel()

        enter("6", into: viewModel)
        viewModel.setOperator(.add)
        enter("6", into: viewModel)
        viewModel.setOperator(.add)

        XCTAssertEqual(viewModel.expressionDisplay, "6 + 6 +")

        viewModel.setOperator(.subtract)

        XCTAssertEqual(viewModel.display, "6")
        XCTAssertEqual(viewModel.expressionDisplay, "6 + 6 −")

        enter("3", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "9")
        XCTAssertEqual(viewModel.expressionDisplay, "6 + 6 − 3 =")
        XCTAssertEqual(viewModel.history.first?.expression, "6 + 6 − 3")
        XCTAssertEqual(viewModel.history.first?.result, "9")
    }

    func testLongMixedOperationChainMatchesReferenceResult() {
        let viewModel = CalculatorViewModel()

        enter("5454", into: viewModel)
        viewModel.setOperator(.add)
        enter("5454", into: viewModel)
        viewModel.setOperator(.add)
        enter("5655", into: viewModel)
        viewModel.setOperator(.subtract)
        enter("5454", into: viewModel)
        viewModel.setOperator(.subtract)
        enter("88", into: viewModel)
        viewModel.setOperator(.subtract)
        enter("555", into: viewModel)
        viewModel.setOperator(.subtract)
        enter("8787", into: viewModel)
        viewModel.setOperator(.subtract)
        enter("32121", into: viewModel)
        viewModel.setOperator(.add)
        enter("54", into: viewModel)
        viewModel.setOperator(.subtract)
        enter("5", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        enter("5454", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("444", into: viewModel)

        let additiveTail = [
            "1", "1", "1", "1", "1", "1", "1", "1", "1", "1", "1",
            "11", "1", "1", "1", "2", "4", "5", "4", "6", "6", "645",
            "1", "1", "11", "1", "1", "1", "1", "11", "1", "1", "11",
            "1", "1", "11", "1", "1", "11", "1", "11", "1", "11", "1",
            "1", "11"
        ]

        for value in additiveTail {
            viewModel.setOperator(.add)
            enter(value, into: viewModel)
        }

        viewModel.setOperator(.add)
        enter("65050083", into: viewModel)
        viewModel.toggleSign()

        let expectedExpression = "( 5,454 + 5,454 + 5,655 − 5,454 − 88 − 555 − 8,787 − 32,121 + 54 − 5 × 5 + 5,454 ) × 444 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 11 + 1 + 1 + 1 + 2 + 4 + 5 + 4 + 6 + 6 + 645 + 1 + 1 + 11 + 1 + 1 + 1 + 1 + 11 + 1 + 1 + 11 + 1 + 1 + 11 + 1 + 1 + 11 + 1 + 11 + 1 + 11 + 1 + 1 + 11 + -65,050,083"
        XCTAssertEqual(viewModel.expressionDisplay, expectedExpression)

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "-76,131,078")
        XCTAssertEqual(viewModel.history.first?.result, "-76131078")
    }

    func testAddingSignToggledNegativeRightOperandUsesLeftAccumulator() {
        let viewModel = CalculatorViewModel()

        enter("10", into: viewModel)
        viewModel.setOperator(.add)
        enter("5", into: viewModel)
        viewModel.toggleSign()

        XCTAssertEqual(viewModel.display, "-5")
        XCTAssertEqual(viewModel.expressionDisplay, "10 + -5")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "5")
        XCTAssertEqual(viewModel.expressionDisplay, "10 + -5 =")
        XCTAssertEqual(viewModel.history.first?.expression, "10 + -5")
        XCTAssertEqual(viewModel.history.first?.result, "5")
    }

    func testUndoRedoRestoresFullChainedExpressionDuringConstruction() {
        let viewModel = CalculatorViewModel()

        enter("2", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("2", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("2", into: viewModel)

        XCTAssertEqual(viewModel.expressionDisplay, "2 × 2 × 2")

        viewModel.undo()
        XCTAssertEqual(viewModel.display, "2")
        XCTAssertEqual(viewModel.expressionDisplay, "2 × 2 ×")

        viewModel.redo()
        XCTAssertEqual(viewModel.display, "2")
        XCTAssertEqual(viewModel.expressionDisplay, "2 × 2 × 2")
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
        XCTAssertEqual(viewModel.expressionDisplay, "(2 + 3) × 4 =")
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

    func testTypingOpenParenthesisAfterPendingRightOperandPreservesThatOperand() {
        let viewModel = CalculatorViewModel()

        enter("6", into: viewModel)
        viewModel.setOperator(.add)
        enter("6", into: viewModel)
        viewModel.inputParenthesis("(")

        XCTAssertEqual(viewModel.expressionDisplay, "6 + 6 × (")

        enter("2", into: viewModel)
        viewModel.inputParenthesis(")")
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "18")
        XCTAssertEqual(viewModel.expressionDisplay, "6 + (6 × 2) =")
        XCTAssertEqual(viewModel.history.first?.expression, "6 + 6 × ( 2 )")
    }

    func testParenthesisKeyPreservesExistingMultiChainExpression() {
        let viewModel = CalculatorViewModel()

        enter("6", into: viewModel)
        viewModel.setOperator(.add)
        enter("6", into: viewModel)
        viewModel.setOperator(.add)
        enter("6", into: viewModel)
        viewModel.inputParentheses()

        XCTAssertEqual(viewModel.expressionDisplay, "6 + 6 + 6 × (")

        enter("2", into: viewModel)
        viewModel.inputParenthesis(")")
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "24")
        XCTAssertEqual(viewModel.expressionDisplay, "6 + 6 + (6 × 2) =")
        XCTAssertEqual(viewModel.history.first?.expression, "6 + 6 + 6 × ( 2 )")
    }

    func testKeyboardTypedNestedParenthesesAreAcceptedInline() {
        let viewModel = CalculatorViewModel()

        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.inputParenthesis("(")
        enter("4", into: viewModel)
        viewModel.setOperator(.add)
        enter("5", into: viewModel)
        viewModel.inputParenthesis("(")
        enter("6", into: viewModel)
        viewModel.inputParenthesis(")")
        viewModel.inputParenthesis(")")

        XCTAssertEqual(viewModel.expressionDisplay, "2 + 3 × ( 4 + 5 × ( 6 ) )")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "104")
        XCTAssertEqual(viewModel.history.first?.expression, "2 + 3 × ( 4 + 5 × ( 6 ) )")
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

    func testSquareOfNegativeInputUsesExponentPrecedenceSemantics() {
        let viewModel = CalculatorViewModel()

        enter("2", into: viewModel)
        viewModel.toggleSign()
        viewModel.square()

        XCTAssertEqual(viewModel.display, "-4")
        XCTAssertEqual(viewModel.expressionDisplay, "-2²")
        XCTAssertEqual(viewModel.history.isEmpty, true)
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
        XCTAssertEqual(viewModel.expressionDisplay, "√(4) × (2 + 2) =")
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
        XCTAssertEqual(viewModel.expressionDisplay, "1/(4) × (2 + 2) =")
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
        XCTAssertEqual(viewModel.expressionDisplay, "3² × (2 + 1) =")
        XCTAssertEqual(viewModel.history.first?.expression, "sqr(3) × ( 2 + 1 )")
        XCTAssertEqual(viewModel.history.first?.displayExpression, "3² × (2 + 1)")
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
        XCTAssertEqual(viewModel.expressionDisplay, "(2 + 3) × (√(4) + 1) =")
        XCTAssertEqual(viewModel.history.first?.expression, "( 2 + 3 ) × ( √(4) + 1 )")
        XCTAssertEqual(viewModel.history.first?.result, "15")
    }

    func testPercentInsideParenthesizedExpressionStaysVisibleUntilEvaluate() {
        let viewModel = CalculatorViewModel()

        enter("1", into: viewModel)
        viewModel.setOperator(.add)
        enter("2", into: viewModel)
        viewModel.setOperator(.multiply)
        viewModel.inputParenthesis("(")
        enter("100", into: viewModel)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "100%")
        XCTAssertEqual(viewModel.expressionDisplay, "1 + 2 × ( 100%")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "3")
        XCTAssertEqual(viewModel.expressionDisplay, "1 + (2 × 100%) =")
        XCTAssertEqual(viewModel.history.first?.expression, "1 + 2 × ( 100% )")
        XCTAssertEqual(viewModel.history.first?.result, "3")
    }

    func testPercentInsideParenthesizedExpressionEvaluatesAsDecimalPercent() {
        let viewModel = CalculatorViewModel()

        enter("1", into: viewModel)
        viewModel.setOperator(.add)
        enter("5", into: viewModel)
        viewModel.setOperator(.multiply)
        viewModel.inputParenthesis("(")
        enter("200", into: viewModel)
        viewModel.applyPercent()
        viewModel.inputParenthesis(")")
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "11")
        XCTAssertEqual(viewModel.expressionDisplay, "1 + (5 × 200%) =")
        XCTAssertEqual(viewModel.history.first?.expression, "1 + 5 × ( 200% )")
        XCTAssertEqual(viewModel.history.first?.result, "11")
    }

    func testPercentConvertsCurrentInputToDecimalValue() {
        let viewModel = CalculatorViewModel()

        enter("50", into: viewModel)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "0.5")
        XCTAssertEqual(viewModel.expressionDisplay, "50%")
        XCTAssertFalse(viewModel.isErrorState)
    }

    func testPercentAfterEvaluateUsesCanonicalBehavior() {
        let viewModel = CalculatorViewModel()

        enter("50", into: viewModel)
        viewModel.evaluate()
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "0.5")
        XCTAssertEqual(viewModel.expressionDisplay, "50%")
        XCTAssertFalse(viewModel.isErrorState)
    }

    func testPercentStandaloneInputUsesCanonicalBehavior() {
        let viewModel = CalculatorViewModel()

        enter("50", into: viewModel)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "0.5")
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
        XCTAssertEqual(viewModel.expressionDisplay, "10 + 10% =")
        XCTAssertEqual(viewModel.history.first?.expression, "10 + 10%")
        XCTAssertEqual(viewModel.history.first?.result, "11")
    }

    func testRepeatedEqualsAfterPercentDoesNotAdvanceResult() {
        let viewModel = CalculatorViewModel()

        enter("100", into: viewModel)
        viewModel.setOperator(.add)
        enter("50", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "150")
        XCTAssertEqual(viewModel.expressionDisplay, "100 + 50% =")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "150")
        XCTAssertEqual(viewModel.expressionDisplay, "100 + 50% =")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "150")
        XCTAssertEqual(viewModel.expressionDisplay, "100 + 50% =")
        XCTAssertEqual(viewModel.history.first?.expression, "100 + 50%")
    }

    func testCurrencyPercentInPendingAdditionStaysVisibleUntilEvaluate() {
        let viewModel = CalculatorViewModel()

        viewModel.inputCurrencySymbol("$")
        enter("6", into: viewModel)
        viewModel.setOperator(.add)
        enter("200", into: viewModel)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "200%")
        XCTAssertEqual(viewModel.expressionDisplay, "6 + 200%")

        viewModel.evaluate()

        // The percent applies to the amount rather than replacing it: 200% of 6
        // is 12, added to the original 6.
        XCTAssertEqual(viewModel.display, "$18")
        XCTAssertEqual(viewModel.expressionDisplay, "6 + 200% =")
        XCTAssertEqual(viewModel.history.first?.expression, "6 + 200%")
        XCTAssertEqual(viewModel.history.first?.result, "$18")
    }

    func testPercentMatchesCalculatorForSubtraction() {
        let viewModel = CalculatorViewModel()

        enter("200", into: viewModel)
        viewModel.setOperator(.subtract)
        enter("10", into: viewModel)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "10%")
        XCTAssertEqual(viewModel.expressionDisplay, "200 − 10%")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "180")
        XCTAssertEqual(viewModel.expressionDisplay, "200 − 10% =")
        XCTAssertEqual(viewModel.history.first?.expression, "200 − 10%")
        XCTAssertEqual(viewModel.history.first?.result, "180")
    }

    func testPercentMatchesCalculatorForDivision() {
        let viewModel = CalculatorViewModel()

        enter("10", into: viewModel)
        viewModel.setOperator(.divide)
        enter("10", into: viewModel)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "10%")
        XCTAssertEqual(viewModel.expressionDisplay, "10 ÷ 10%")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "100")
        XCTAssertEqual(viewModel.expressionDisplay, "10 ÷ 10% =")
        XCTAssertEqual(viewModel.history.first?.expression, "10 ÷ 10%")
        XCTAssertEqual(viewModel.history.first?.result, "100")
    }

    func testPercentMatchesCalculatorForMultiplication() {
        let viewModel = CalculatorViewModel()

        enter("100", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("15", into: viewModel)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "15%")
        XCTAssertEqual(viewModel.expressionDisplay, "100 × 15%")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "15")
        XCTAssertEqual(viewModel.expressionDisplay, "100 × 15% =")
        XCTAssertEqual(viewModel.history.first?.expression, "100 × 15%")
        XCTAssertEqual(viewModel.history.first?.result, "15")
    }

    func testDivisionWithTwoHundredPercentKeepsPercentVisibleUntilEvaluate() {
        let viewModel = CalculatorViewModel()

        enter("5", into: viewModel)
        viewModel.setOperator(.divide)
        enter("200", into: viewModel)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "200%")
        XCTAssertEqual(viewModel.expressionDisplay, "5 ÷ 200%")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "2.5")
        XCTAssertEqual(viewModel.expressionDisplay, "5 ÷ 200% =")
        XCTAssertEqual(viewModel.history.first?.expression, "5 ÷ 200%")
        XCTAssertEqual(viewModel.history.first?.result, "2.5")
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

        // Adding two percentages keeps percent form in the result; the stored
        // value stays the decimal so later arithmetic is unaffected.
        XCTAssertEqual(viewModel.display, "8%")
        XCTAssertEqual(viewModel.expressionDisplay, "5% + 3% =")
        XCTAssertEqual(viewModel.history.first?.expression, "5% + 3%")
        XCTAssertEqual(viewModel.history.first?.result, "0.08")
        XCTAssertEqual(viewModel.history.first?.displayResult, "8%")
    }

    func testPercentPlusPercentKeepsPercentInResult() {
        let viewModel = CalculatorViewModel()

        enter("9", into: viewModel)
        viewModel.applyPercent()
        viewModel.setOperator(.add)
        enter("9", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "18%")
        XCTAssertEqual(viewModel.expressionDisplay, "9% + 9% =")
    }

    // Currency mode uses the same percent semantics as plain entry: a percent
    // added to an amount is a share *of* that amount, so $10 + 10% is $11 —
    // 10 × 1.1 — not the $1 the percentage is worth on its own.
    func testCurrencyPercentAdditionAppliesToTheAmount() {
        let viewModel = CalculatorViewModel()

        enter("10", into: viewModel)
        viewModel.inputCurrencySymbol("$")
        viewModel.setOperator(.add)
        enter("10", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "$11")
    }

    func testCurrencyPercentAdditionMatchesPlainPercentAddition() {
        let currency = CalculatorViewModel()
        enter("10", into: currency)
        currency.inputCurrencySymbol("$")
        currency.setOperator(.add)
        enter("25", into: currency)
        currency.applyPercent()
        currency.evaluate()

        let plain = CalculatorViewModel()
        enter("10", into: plain)
        plain.setOperator(.add)
        enter("25", into: plain)
        plain.applyPercent()
        plain.evaluate()

        XCTAssertEqual(currency.display, "$12.5")
        XCTAssertEqual(plain.display, "12.5")
    }

    // Only percent handling changes in currency mode. Adding a plain decimal is
    // still ordinary addition.
    func testCurrencyPlainDecimalAdditionIsUnchanged() {
        let viewModel = CalculatorViewModel()

        enter("10", into: viewModel)
        viewModel.inputCurrencySymbol("$")
        viewModel.setOperator(.add)
        enter("0.25", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "$10.25")
    }

    func testCurrencyPercentSubtractionAppliesToTheAmount() {
        let viewModel = CalculatorViewModel()

        enter("200", into: viewModel)
        viewModel.inputCurrencySymbol("$")
        viewModel.setOperator(.subtract)
        enter("10", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "$180")
    }

    func testPercentMinusPercentKeepsPercentInResult() {
        let viewModel = CalculatorViewModel()

        enter("10", into: viewModel)
        viewModel.applyPercent()
        viewModel.setOperator(.subtract)
        enter("4", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "6%")
        XCTAssertEqual(viewModel.expressionDisplay, "10% − 4% =")
    }

    // Only percent-plus-percent carries the symbol through. A percent applied to
    // a plain operand is a share *of* that operand, so its result is a value.
    func testPercentAddedToPlainNumberStillResolvesToValue() {
        let viewModel = CalculatorViewModel()

        enter("200", into: viewModel)
        viewModel.setOperator(.add)
        enter("10", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "220")
    }

    // × and ÷ keep decimal semantics: 9% × 9% is 0.81%, not 81%, so rendering a
    // percent symbol there would misstate the result.
    func testPercentTimesPercentStaysDecimal() {
        let viewModel = CalculatorViewModel()

        enter("9", into: viewModel)
        viewModel.applyPercent()
        viewModel.setOperator(.multiply)
        enter("9", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "0.0081")
    }

    // The percent result is a display form over a decimal value, so continuing
    // to calculate uses the underlying 0.18 rather than 18.
    func testCalculationContinuingFromPercentResultUsesDecimalValue() {
        let viewModel = CalculatorViewModel()

        enter("9", into: viewModel)
        viewModel.applyPercent()
        viewModel.setOperator(.add)
        enter("9", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()
        viewModel.setOperator(.add)
        enter("1", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "1.18")
    }

    // Guards against the result token being re-wrapped into "18%%": applying %
    // to an "18%" result has to work from the stored 0.18, matching how % on any
    // other value behaves.
    func testPercentPressedOnPercentResultUsesUnderlyingValue() {
        let viewModel = CalculatorViewModel()

        enter("9", into: viewModel)
        viewModel.applyPercent()
        viewModel.setOperator(.add)
        enter("9", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "0.0018")
        XCTAssertEqual(viewModel.expressionDisplay, "0.18%")
    }

    func testUndoAfterPercentPlusPercentRestoresPendingPercentState() {
        let viewModel = CalculatorViewModel()

        enter("9", into: viewModel)
        viewModel.applyPercent()
        viewModel.setOperator(.add)
        enter("9", into: viewModel)
        viewModel.applyPercent()
        viewModel.evaluate()
        XCTAssertEqual(viewModel.display, "18%")

        viewModel.undo()

        XCTAssertEqual(viewModel.display, "9%")
        XCTAssertEqual(viewModel.expressionDisplay, "9% + 9%")
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

    func testBackspaceOnInvalidInputUndoesErrorOnce() {
        let viewModel = CalculatorViewModel()

        enter("9", into: viewModel)
        viewModel.toggleSign()
        viewModel.squareRoot()

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "Invalid input")

        viewModel.backspace()

        XCTAssertFalse(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, "-9")
        XCTAssertEqual(viewModel.expressionDisplay, "")
    }

    func testBackspaceOnPendingExpressionDoesNotAutoEvaluateAndKeepsRollbackEditable() {
        let viewModel = CalculatorViewModel()

        enter("3", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)

        viewModel.backspace()
        XCTAssertEqual(viewModel.expressionDisplay, "3 + 3 + 3 +")

        viewModel.backspace()
        XCTAssertEqual(viewModel.expressionDisplay, "3 + 3 + 3")
        XCTAssertEqual(viewModel.display, "3")

        viewModel.backspace()
        XCTAssertEqual(viewModel.expressionDisplay, "3 + 3 +")
        XCTAssertEqual(viewModel.display, "")

        viewModel.backspace()
        XCTAssertEqual(viewModel.expressionDisplay, "3 + 3")
        XCTAssertEqual(viewModel.display, "3")
        XCTAssertTrue(viewModel.history.isEmpty)
    }

    func testClearEntryOnPendingExpressionDoesNotAutoEvaluateOrMutateOperationLine() {
        let viewModel = CalculatorViewModel()

        enter("3", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.setOperator(.add)

        let displayBeforeClear = viewModel.display
        let expressionBeforeClear = viewModel.expressionDisplay

        viewModel.clearEntry()

        XCTAssertEqual(viewModel.display, displayBeforeClear)
        XCTAssertEqual(viewModel.expressionDisplay, expressionBeforeClear)
        XCTAssertTrue(viewModel.history.isEmpty)

        viewModel.evaluate()
        XCTAssertEqual(viewModel.display, "12")
    }

    func testBackspaceRemovingFinalDigitAlsoRemovesExpressionOperandWithoutExtraStep() {
        let viewModel = CalculatorViewModel()

        enter("6", into: viewModel)
        viewModel.setOperator(.add)
        enter("55", into: viewModel)
        viewModel.setOperator(.add)
        enter("777", into: viewModel)
        viewModel.setOperator(.add)
        enter("8888", into: viewModel)

        for _ in 0..<5 {
            viewModel.backspace()
        }
        XCTAssertEqual(viewModel.expressionDisplay, "6 + 55 + 777")

        viewModel.backspace()
        viewModel.backspace()
        viewModel.backspace()

        XCTAssertEqual(viewModel.expressionDisplay, "6 + 55 +")
        XCTAssertTrue(viewModel.history.isEmpty)
    }

    func testClearAllFromPendingExpressionClearsDisplayAndOperationLine() {
        let viewModel = CalculatorViewModel()

        enter("6", into: viewModel)
        viewModel.setOperator(.add)
        enter("55", into: viewModel)
        viewModel.setOperator(.add)
        enter("777", into: viewModel)

        XCTAssertEqual(viewModel.expressionDisplay, "6 + 55 + 777")

        viewModel.clearAll()

        XCTAssertEqual(viewModel.display, "0")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertTrue(viewModel.history.isEmpty)
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
        let expectedOldestRetainedExpression = "\(totalEvaluations - retainedEntryCount + 1) + 1"

        for value in 1...totalEvaluations {
            viewModel.clearAll()
            enter("\(value)", into: viewModel)
            viewModel.setOperator(.add)
            enter("1", into: viewModel)
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

    func testOperationChunkLimitMatchesUndoDepthLimit() {
        XCTAssertEqual(
            CalculatorViewModel.Limits.maxOperationChunks,
            CalculatorViewModel.Limits.maxUndoDepth
        )
    }

    func testOperationChunkCountIsCappedAtMaximumUndoDepth() {
        let viewModel = CalculatorViewModel()
        let maxChunks = CalculatorViewModel.Limits.maxOperationChunks

        enter("1", into: viewModel)
        if maxChunks > 1 {
            for value in 2...maxChunks {
                viewModel.setOperator(.add)
                enter(String(value), into: viewModel)
            }
        }

        let expressionBeforeExtraOperator = viewModel.expressionDisplay

        // At the chunk cap, adding another operator should be a no-op.
        viewModel.setOperator(.add)

        XCTAssertEqual(viewModel.expressionDisplay, expressionBeforeExtraOperator)

        viewModel.evaluate()

        let expectedTotal = (maxChunks * (maxChunks + 1)) / 2
        XCTAssertEqual(viewModel.history.first?.result, String(expectedTotal))
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
            $0.usesAlternativeKeypad = true
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

    func testCopyLocalizationKeysExistAcrossSupportedBundles() throws {
        let localeCodes = ["Base", "en", "de", "es", "fr", "ja", "zh-Hans"]
        let copyKeys = [
            "copy.copied"
        ]

        for localeCode in localeCodes {
            let strings = try localizedStrings(named: localeCode)
            for key in copyKeys {
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
    func testCopyToPasteboardWritesDisplayedGroupedValue() {
        let viewModel = CalculatorViewModel()

        enter("1234", into: viewModel)
        viewModel.copyToPasteboard()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "1,234")
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
        viewModel.beginResultRounding()
        viewModel.setResultRoundingPrecision(4)
        XCTAssertEqual(viewModel.display, "9.3")

        viewModel.copyToPasteboard()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "9.3")
    }

    func testCommitResultRoundingDoesNotAppendHistoryForIncompletePendingOperation() {
        let viewModel = CalculatorViewModel()

        enter("12", into: viewModel)
        viewModel.setOperator(.add)
        viewModel.beginResultRounding()
        viewModel.setResultRoundingPrecision(4)
        viewModel.commitResultRoundingInteraction()

        XCTAssertTrue(viewModel.history.isEmpty)
    }

    func testOpenThenCloseResultRoundingDoesNotAppendHistory() {
        let viewModel = CalculatorViewModel()

        pasteString("9.32227", into: viewModel)
        viewModel.beginResultRounding()
        viewModel.commitResultRoundingInteraction()

        XCTAssertTrue(viewModel.history.isEmpty)
        XCTAssertEqual(viewModel.display, "9.32227")
        XCTAssertFalse(viewModel.isResultRoundingEnabled)
    }

    func testExactRoundingUsesEqualsAndPreservesSelectedSignificantDigits() throws {
        let viewModel = CalculatorViewModel()

        pasteString("5", into: viewModel)
        viewModel.beginResultRounding()
        viewModel.setResultRoundingPrecision(3)

        XCTAssertEqual(viewModel.display, "5")
        XCTAssertEqual(viewModel.expressionDisplay, "=round(5, 0)")

        viewModel.commitResultRoundingInteraction()

        let entry = try XCTUnwrap(viewModel.history.first)
        XCTAssertEqual(entry.expression, "round(5, 3)")
        XCTAssertEqual(entry.result, "5")
        XCTAssertEqual(entry.displayResult, "5")
        XCTAssertEqual(entry.displayExpression, "=round(5, 0)")

        viewModel.copyOperationToPasteboard(entry)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "=round(5,0)")
    }

    func testRoundedOperationCopyOmitsCurrencySymbols() throws {
        let viewModel = CalculatorViewModel()

        pasteString("$5", into: viewModel)
        viewModel.beginResultRounding()
        viewModel.setResultRoundingPrecision(3)

        XCTAssertEqual(viewModel.expressionDisplay, "=round(5, 0)")

        viewModel.copyOperationToPasteboard()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "=round(5,0)")

        viewModel.commitResultRoundingInteraction()

        let entry = try XCTUnwrap(viewModel.history.first)
        XCTAssertEqual(entry.displayExpression, "=round(5, 0)")

        viewModel.copyOperationToPasteboard(entry)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "=round(5,0)")
    }

    func testCurrencyRoundingDisplaysTwoDecimalsWithoutNormalPadding() throws {
        let viewModel = CalculatorViewModel()

        pasteString("$5", into: viewModel)
        XCTAssertEqual(viewModel.display, "$5")

        viewModel.beginResultRounding()
        viewModel.setResultRoundingPrecision(3)

        XCTAssertEqual(viewModel.display, "$5.00")

        viewModel.copyToPasteboard()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "$5.00")

        viewModel.commitResultRoundingInteraction()

        let entry = try XCTUnwrap(viewModel.history.first)
        XCTAssertEqual(entry.displayResult, "$5.00")
    }

    func testResultRoundingLevelsRoundFromLeastSignificantDigit() {
        let viewModel = CalculatorViewModel()

        pasteString("54321", into: viewModel)
        viewModel.beginResultRounding()
        viewModel.setResultRoundingPrecision(1)
        XCTAssertEqual(viewModel.display, "54,320")

        viewModel.setResultRoundingPrecision(2)
        XCTAssertEqual(viewModel.display, "54,300")

        viewModel.setResultRoundingPrecision(5)
        XCTAssertEqual(viewModel.display, "50,000")

        viewModel.removeResultRounding()
        XCTAssertEqual(viewModel.display, "54,321")

        pasteString("1.5678", into: viewModel)
        viewModel.beginResultRounding()
        viewModel.setResultRoundingPrecision(1)
        XCTAssertEqual(viewModel.display, "1.568")

        viewModel.setResultRoundingPrecision(2)
        XCTAssertEqual(viewModel.display, "1.57")

        viewModel.setResultRoundingPrecision(8)
        XCTAssertEqual(viewModel.display, "2")

        viewModel.removeResultRounding()
        XCTAssertEqual(viewModel.display, "1.5678")
    }

    func testResultRoundingCollapsesEvaluatedExpressionToCurrentTotal() {
        let viewModel = CalculatorViewModel()

        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        pasteString("2.33", into: viewModel)
        viewModel.evaluate()

        viewModel.beginResultRounding()
        viewModel.setResultRoundingPrecision(1)

        XCTAssertEqual(viewModel.display, "4.3")
        XCTAssertEqual(viewModel.expressionDisplay, "=round(4.33, 1) ≈")
    }

    func testBackspaceUpdatesRoundedOperationBaseValue() {
        let viewModel = CalculatorViewModel()

        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        pasteString("2.33", into: viewModel)
        viewModel.evaluate()
        viewModel.beginResultRounding()
        viewModel.setResultRoundingPrecision(1)

        viewModel.backspace()

        XCTAssertEqual(viewModel.display, "0")
        XCTAssertEqual(viewModel.expressionDisplay, "=round(0, 0)")
    }

    // MARK: Regression: rounding precision must not drift during further input
    /// Before the fix, when the user typed a RHS operand with more decimal digits than the
    /// LHS, `updateDisplay` passed `currentInput` (the RHS) as the `sourceValue` for
    /// `spreadsheetRoundScale`, causing the displayed scale to change on every keystroke.
    /// After the fix the scale is anchored to the accumulated LHS while typing.
    func testRoundingOperationScaleRemainsAnchoredToLHSWhileTypingRHSOperand() {
        let viewModel = CalculatorViewModel()

        // Enter LHS and enable rounding at precision 4.
        // For "10.123456" (8 sig-digits) and precision 4:
        //   effectiveLevels = min(4, 7) = 4, retainedDigits = 4, magnitude = 1
        //   spreadsheetRoundScale = 4 − 1 − 1 = 2
        pasteString("10.123456", into: viewModel)
        viewModel.beginResultRounding()
        viewModel.setResultRoundingPrecision(4)
        XCTAssertEqual(viewModel.expressionDisplay, "=round(10.123456, 2) ≈")

        viewModel.setOperator(.add)

        // Type the RHS operand digit-by-digit (using enter rather than pasteString so
        // pasting a plain value does not reset the rounding state).  The old code
        // would recompute the scale from "0.0999999999" (9 sig-digits, magnitude ≈ −2,
        // scale ≈ 6) and show "=round(…, 6) ≈".  With the fix the scale stays at 2
        // (anchored to the accumulated LHS value "10.123456").
        enter("0.0999999999", into: viewModel)
        XCTAssertEqual(viewModel.expressionDisplay, "=round(10.123456 + 0.0999999999, 2) ≈")
    }

    /// Before the fix, the display rounded the RHS operand while it was being typed
    /// (e.g. "0.0999999999" collapsed to "0.1"), making in-progress input invisible.
    /// After the fix the raw typed value is preserved in the display during a pending op.
    func testRoundingDisplayIsNotPrematurelyAppliedWhileTypingRHSOperand() {
        let viewModel = CalculatorViewModel()

        pasteString("10.123456", into: viewModel)
        viewModel.beginResultRounding()
        viewModel.setResultRoundingPrecision(4)
        viewModel.setOperator(.add)

        // Type a 10-significant-digit RHS digit-by-digit.  Without the fix the
        // display would show the rounded value "0.1" while the user is still
        // entering digits.  With the fix the full typed value is preserved.
        enter("0.0999999999", into: viewModel)
        XCTAssertEqual(viewModel.display, "0.0999999999")
    }

    /// Verify that precision=4 is still applied correctly after equals: the expression
    /// display reflects the scale computed from the actual result value, and the numeric
    /// display shows the correctly-rounded result.
    func testRoundingFinalResultAfterPendingOperationUsesResultBasedScale() {
        let viewModel = CalculatorViewModel()

        pasteString("10.123456", into: viewModel)
        viewModel.beginResultRounding()
        viewModel.setResultRoundingPrecision(4)
        viewModel.setOperator(.add)
        enter("0.0999999999", into: viewModel)
        viewModel.evaluate()

        // Result = 10.2234559999 (12 significant digits).
        // effectiveLevels = min(4, 11) = 4, retainedDigits = 8, magnitude = 1
        // spreadsheetRoundScale = 8 − 1 − 1 = 6
        // NSDecimalRound(10.2234559999, 6) = 10.223456
        XCTAssertEqual(viewModel.display, "10.223456")
        XCTAssertEqual(viewModel.expressionDisplay, "=round(10.2234559999, 6) ≈")
    }

    /// Ensure no precision change occurs on the internal `resultRoundingPrecision` property
    /// when more digits are typed after enabling rounding.
    func testResultRoundingPrecisionPropertyRemainsFixedDuringFurtherInput() {
        let viewModel = CalculatorViewModel()

        pasteString("10.123456", into: viewModel)
        viewModel.beginResultRounding()
        viewModel.setResultRoundingPrecision(4)
        XCTAssertEqual(viewModel.resultRoundingPrecision, 4)

        viewModel.setOperator(.add)
        enter("0.0999999999", into: viewModel)
        XCTAssertEqual(viewModel.resultRoundingPrecision, 4)

        viewModel.evaluate()
        XCTAssertEqual(viewModel.resultRoundingPrecision, 4)
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

        XCTAssertEqual(viewModel.display, "$1,234.5")
        XCTAssertFalse(viewModel.isErrorState)
    }

    func testLeadingCurrencyPasteKeepsCurrencyActiveUntilAllClear() {
        let viewModel = CalculatorViewModel()

        pasteString("$12.3", into: viewModel)
        XCTAssertEqual(viewModel.display, "$12.3")

        viewModel.setOperator(.add)
        enter("1", into: viewModel)
        XCTAssertEqual(viewModel.expressionDisplay, "12.3 + 1")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "$13.3")
        XCTAssertEqual(viewModel.history.first?.displayExpression, "12.3 + 1")
        XCTAssertEqual(viewModel.history.first?.displayResult, "$13.3")

        viewModel.clearAll()
        XCTAssertEqual(viewModel.display, "0")
    }

    func testCurrencyReuseRestoresCurrencyAwareState() throws {
        let viewModel = CalculatorViewModel()

        pasteString("€12.34", into: viewModel)
        viewModel.setOperator(.add)
        enter("1", into: viewModel)
        viewModel.evaluate()

        let entry = try XCTUnwrap(viewModel.history.first)
        XCTAssertEqual(entry.displayExpression, "12.34 + 1")
        XCTAssertEqual(entry.displayResult, "€13.34")

        viewModel.clearAll()
        viewModel.reuse(entry)

        XCTAssertEqual(viewModel.display, "€13.34")
        XCTAssertEqual(viewModel.expressionDisplay, "12.34 + 1 =")
    }

    func testCurrencyOperationCopyThenPasteReplaysAndRestoresCurrencyMode() {
        let sourceViewModel = CalculatorViewModel()

        pasteString("$12.34", into: sourceViewModel)
        sourceViewModel.setOperator(.add)
        enter("1", into: sourceViewModel)
        sourceViewModel.evaluate()
        sourceViewModel.copyOperationToPasteboard()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "12.34 + 1 = $13.34")

        let pastedViewModel = CalculatorViewModel()
        pastedViewModel.pasteFromPasteboard()

        XCTAssertEqual(pastedViewModel.display, "$13.34")
        XCTAssertEqual(pastedViewModel.expressionDisplay, "12.34 + 1 =")
        XCTAssertFalse(pastedViewModel.isErrorState)
    }

    func testTypingCurrencySymbolActivatesCurrencyFormatting() {
        let viewModel = CalculatorViewModel()

        viewModel.inputCurrencySymbol("$")
        enter("1", into: viewModel)
        viewModel.inputDecimal()
        enter("2", into: viewModel)

        XCTAssertEqual(viewModel.display, "$1.2")

        viewModel.setOperator(.add)
        enter("2", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "$3.2")
    }

    func testTypingCurrencySymbolMidChainKeepsExistingExpression() {
        let viewModel = CalculatorViewModel()

        enter("10", into: viewModel)
        viewModel.setOperator(.add)
        enter("5", into: viewModel)
        viewModel.setOperator(.multiply)

        XCTAssertEqual(viewModel.expressionDisplay, "10 + 5 ×")
        XCTAssertEqual(viewModel.display, "5")

        viewModel.inputCurrencySymbol("$")

        XCTAssertEqual(viewModel.expressionDisplay, "10 + 5 ×")
        XCTAssertEqual(viewModel.display, "$5")

        enter("2", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "$20")
        XCTAssertEqual(viewModel.history.first?.displayExpression, "10 + (5 × 2)")
    }

    func testStackedOperationDisplayPreservesSubtractTermsAfterEvaluate() {
        let viewModel = CalculatorViewModel()

        enter("25", into: viewModel)
        viewModel.setOperator(.add)
        viewModel.inputParenthesis("(")
        enter("6", into: viewModel)
        viewModel.setOperator(.add)
        enter("65", into: viewModel)
        viewModel.setOperator(.add)
        enter("665", into: viewModel)
        viewModel.setOperator(.subtract)
        enter("554", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("5454", into: viewModel)
        viewModel.setOperator(.add)
        enter("65659", into: viewModel)
        viewModel.setOperator(.subtract)
        enter("44", into: viewModel)
        viewModel.inputDecimal()
        enter("00022", into: viewModel)
        viewModel.setOperator(.add)
        enter("11", into: viewModel)
        viewModel.inputDecimal()
        enter("22244", into: viewModel)
        viewModel.setOperator(.add)
        enter("8", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "-2,955,120.77778")
        XCTAssertTrue(viewModel.expressionDisplay.contains("− (554 × 5,454)"))
        XCTAssertTrue(viewModel.expressionDisplay.contains("− 44.00022"))
        XCTAssertFalse(viewModel.expressionDisplay.contains("+ (554 × 5,454)"))
        XCTAssertFalse(viewModel.expressionDisplay.contains("+ 44.00022"))
    }

    func testTypingCurrencyZerosPreservesLiveFractionPrecision() {
        let viewModel = CalculatorViewModel()

        viewModel.inputCurrencySymbol("$")
        viewModel.inputDecimal()
        XCTAssertEqual(viewModel.display, "$0.")

        viewModel.inputDigit("0")
        XCTAssertEqual(viewModel.display, "$0.0")

        viewModel.inputDigit("0")
        viewModel.inputDigit("0")
        XCTAssertEqual(viewModel.display, "$0.000")

        enter("43", into: viewModel)
        XCTAssertEqual(viewModel.display, "$0.00043")

        viewModel.copyToPasteboard()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "$0.00043")
    }

    func testBitcoinCurrencySymbolIsSupported() {
        let viewModel = CalculatorViewModel()

        viewModel.inputCurrencySymbol("₿")
        enter("1", into: viewModel)
        viewModel.inputDecimal()
        enter("2", into: viewModel)

        XCTAssertEqual(viewModel.display, "₿1.2")

        viewModel.copyToPasteboard()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "₿1.2")
    }

    func testPastingBitcoinCurrencyPreservesExtendedFractionPrecision() {
        let viewModel = CalculatorViewModel()

        pasteString("₿1.00043", into: viewModel)

        XCTAssertEqual(viewModel.display, "₿1.00043")

        viewModel.copyToPasteboard()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "₿1.00043")
    }

    func testPastingCentsNotationConvertsToDollarCurrencyMode() {
        let viewModel = CalculatorViewModel()

        pasteString("12¢", into: viewModel)

        XCTAssertEqual(viewModel.display, "$0.12")

        viewModel.copyToPasteboard()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "$0.12")
    }

    func testCurrencyCopyUsesActiveNumberStyleDecimalSeparator() {
        let viewModel = CalculatorViewModel(numberFormatStyle: .french)

        pasteString("€1,2", into: viewModel)
        XCTAssertEqual(viewModel.display, "€1,2")

        viewModel.copyToPasteboard()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "€1,2")
    }

    func testCurrencyModePercentOverridesCurrencyInMultiplyExpression() {
        let viewModel = CalculatorViewModel()

        pasteString("$100", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("115", into: viewModel)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "115%")
        XCTAssertEqual(viewModel.expressionDisplay, "100 × 115%")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "$115")
        XCTAssertEqual(viewModel.expressionDisplay, "100 × 115% =")
        XCTAssertEqual(viewModel.history.first?.displayExpression, "100 × 115%")
        XCTAssertEqual(viewModel.history.first?.displayResult, "$115")
    }

    func testCurrencyModePercentOverridesCurrencyInDivisionExpression() {
        let viewModel = CalculatorViewModel()

        pasteString("€93.33", into: viewModel)
        viewModel.setOperator(.divide)
        enter("60", into: viewModel)
        viewModel.applyPercent()

        XCTAssertEqual(viewModel.display, "60%")
        XCTAssertEqual(viewModel.expressionDisplay, "93.33 ÷ 60%")

        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "€155.55")
        XCTAssertEqual(viewModel.expressionDisplay, "93.33 ÷ 60% =")
        XCTAssertEqual(viewModel.history.first?.displayExpression, "93.33 ÷ 60%")
        XCTAssertEqual(viewModel.history.first?.displayResult, "€155.55")
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
        usesAlternativeKeypad: Bool = false
    ) -> CalculatorScreenSettings {
        CalculatorScreenSettings(
            themeRawValue: themeRawValue,
            languageCode: languageCode,
            usesScientificNotation: usesScientificNotation,
            numberFormatStyleRawValue: numberFormatStyleRawValue,
            usesAlternativeKeypad: usesAlternativeKeypad
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

    func testEvaluateAfterTrailingMultiplyOperatorDoesNotDuplicateOperandIntoOverflow() {
        let viewModel = CalculatorViewModel()

        // Get to ≈7.9e28 via five squarings of 8 (still in-range), then press
        // multiply and evaluate without a right operand. This must finalize the
        // existing value rather than duplicating the operand into an overflow.
        enter("8", into: viewModel)
        for _ in 0..<5 { viewModel.square() }
        let expectedDisplay = viewModel.display
        XCTAssertFalse(viewModel.isErrorState, "Pre-condition: value should be valid before multiply")

        viewModel.setOperator(.multiply)
        viewModel.evaluate()

        XCTAssertFalse(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, expectedDisplay)
        XCTAssertEqual(viewModel.history.count, 1)
        // The stored history entry must not include the trailing operator and
        // must record the pre-multiply value, not a doubled/overflowed result.
        XCTAssertEqual(viewModel.history.first?.result, expectedDisplay)
        XCTAssertFalse(viewModel.history.first?.expression.hasSuffix("×") ?? true,
                       "History expression must not end with trailing operator")
    }

    func testOverflowKeepsOperationRowEmptyAndOperationCopyUnavailable() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        for _ in 0..<6 { viewModel.square() }

        XCTAssertTrue(viewModel.isErrorState)
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertFalse(viewModel.hasOperationToCopy)
    }

    func testRepeatedEqualsAfterLargeProductDoesNotOverflowAgain() {
        let viewModel = CalculatorViewModel()

        enter("999999999999999", into: viewModel)
        viewModel.setOperator(.multiply)
        enter("999999999999999", into: viewModel)
        viewModel.evaluate()

        XCTAssertFalse(viewModel.isErrorState)
        let displayAfterFirstEvaluate = viewModel.display
        let expressionAfterFirstEvaluate = viewModel.expressionDisplay

        viewModel.evaluate()

        XCTAssertFalse(viewModel.isErrorState)
        XCTAssertEqual(viewModel.display, displayAfterFirstEvaluate)
        XCTAssertEqual(viewModel.expressionDisplay, expressionAfterFirstEvaluate)
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

    func testReciprocalChainAtLimitStillComputes() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        for _ in 0..<CalculatorViewModel.Limits.maxConsecutiveSquareOrRootDepth {
            viewModel.reciprocal()
        }

        XCTAssertFalse(viewModel.isErrorState)
    }

    func testReciprocalChainBeyondLimitSetsOutOfRange() {
        let viewModel = CalculatorViewModel()

        enter("8", into: viewModel)
        for _ in 0..<(CalculatorViewModel.Limits.maxConsecutiveSquareOrRootDepth + 1) {
            viewModel.reciprocal()
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

    func testMalformedPasteAfterPendingClearKeepsPendingClearState() {
        let viewModel = CalculatorViewModel()

        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.clearEntry()

        let undoDepthBeforePaste = viewModel.undoDepth
        pasteString("1e999999", into: viewModel)

        XCTAssertEqual(viewModel.display, "")
        XCTAssertEqual(viewModel.expressionDisplay, "5 +")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)
        XCTAssertEqual(viewModel.undoDepth, undoDepthBeforePaste)
    }

    // MARK: - Contextual Clear Button Behavior Tests

    func testClearEntryKeepsPendingOperation() {
        let viewModel = CalculatorViewModel()
        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)

        viewModel.clearEntry()

        // Display should be blank while RHS entry is cleared.
        XCTAssertEqual(viewModel.display, "")
        XCTAssertEqual(viewModel.expressionDisplay, "5 +")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)

        // Enter a new value and evaluate - should still add to 5
        enter("7", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "12")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)
    }

    func testClearAllRemovesPendingOperation() {
        let viewModel = CalculatorViewModel()
        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)

        viewModel.clearEntry()
        XCTAssertTrue(viewModel.shouldShowAllClearButton)

        // Pressing clear again in blank pending-entry state should perform AC.
        viewModel.clearEntry()

        // Display should be cleared to 0
        XCTAssertEqual(viewModel.display, "0")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)

        // Enter a new value and evaluate - should NOT add to 5
        enter("7", into: viewModel)
        viewModel.evaluate()

        // Result should be 7, not 12, since the operation was cleared
        XCTAssertEqual(viewModel.display, "7")
    }

    func testClearEntryAfterOperationCanThenContinue() {
        let viewModel = CalculatorViewModel()
        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.clearEntry()
        enter("7", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "12")
    }

    func testClearEntryRemovesPendingOperatorWhenNoRightHandEntry() {
        let viewModel = CalculatorViewModel()
        enter("9", into: viewModel)
        viewModel.setOperator(.multiply)

        viewModel.clearEntry()

        XCTAssertEqual(viewModel.display, "9")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)

        viewModel.clearEntry()

        XCTAssertEqual(viewModel.display, "0")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)

        enter("7", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "7")
    }

    func testInitialStateShowsAllClearButton() {
        let viewModel = CalculatorViewModel()

        XCTAssertEqual(viewModel.display, "0")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)
    }

    func testClearAfterEqualsUsesAllClearImmediately() {
        let viewModel = CalculatorViewModel()

        enter("195", into: viewModel)
        viewModel.setOperator(.add)
        enter("65", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "260")
        XCTAssertEqual(viewModel.expressionDisplay, "195 + 65 =")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)

        viewModel.clearEntry()

        XCTAssertEqual(viewModel.display, "0")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)

        enter("7", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "7")
    }

    func testDigitAfterAllClearFromEvaluatedResultStartsFreshCalculation() {
        let viewModel = CalculatorViewModel()

        enter("195", into: viewModel)
        viewModel.setOperator(.add)
        enter("65", into: viewModel)
        viewModel.evaluate()

        viewModel.clearEntry()
        enter("7", into: viewModel)

        XCTAssertEqual(viewModel.display, "7")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertFalse(viewModel.shouldShowAllClearButton)
    }

    func testClearAfterStandaloneSquareRootUsesAllClearBehavior() {
        let viewModel = CalculatorViewModel()
        enter("8", into: viewModel)
        viewModel.squareRoot()

        XCTAssertTrue(viewModel.shouldShowAllClearButton)
        viewModel.clearEntry()

        XCTAssertEqual(viewModel.display, "0")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)
    }

    func testClearAfterStandaloneSquareUsesAllClearBehavior() {
        let viewModel = CalculatorViewModel()
        enter("8", into: viewModel)
        viewModel.square()

        XCTAssertTrue(viewModel.shouldShowAllClearButton)
        viewModel.clearEntry()

        XCTAssertEqual(viewModel.display, "0")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)
    }

    func testClearAfterStandaloneReciprocalUsesAllClearBehavior() {
        let viewModel = CalculatorViewModel()
        enter("8", into: viewModel)
        viewModel.reciprocal()

        XCTAssertTrue(viewModel.shouldShowAllClearButton)
        viewModel.clearEntry()

        XCTAssertEqual(viewModel.display, "0")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)
    }

    func testClearInsideParenthesesRollsBackToOuterOperation() {
        let viewModel = CalculatorViewModel()

        enter("9", into: viewModel)
        viewModel.setOperator(.multiply)
        viewModel.inputParentheses()
        enter("985", into: viewModel)
        viewModel.setOperator(.add)
        enter("1", into: viewModel)

        viewModel.clearEntry()

        XCTAssertEqual(viewModel.display, "")
        XCTAssertEqual(viewModel.expressionDisplay, "9 ×")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)

        viewModel.clearEntry()

        XCTAssertEqual(viewModel.display, "0")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)
    }

    func testSecondClearFromBlankPendingEntryAddsSingleUndoStep() {
        let viewModel = CalculatorViewModel()

        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.clearEntry()

        let undoDepthBeforeSecondClear = viewModel.undoDepth
        viewModel.clearEntry()

        XCTAssertEqual(viewModel.undoDepth, undoDepthBeforeSecondClear + 1)
    }

    func testBackspaceCanRemovePendingDigitOperatorAndLeftOperand() {
        let viewModel = CalculatorViewModel()

        enter("9", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)

        viewModel.backspace()

        XCTAssertEqual(viewModel.display, "")
        XCTAssertEqual(viewModel.expressionDisplay, "9 +")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)

        viewModel.backspace()

        XCTAssertEqual(viewModel.display, "9")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertFalse(viewModel.shouldShowAllClearButton)

        viewModel.backspace()

        XCTAssertEqual(viewModel.display, "0")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)
    }

    func testBackspaceDeletingStandaloneDigitResetsToFreshAllClearState() {
        let viewModel = CalculatorViewModel()

        enter("3", into: viewModel)

        viewModel.backspace()

        XCTAssertEqual(viewModel.display, "0")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)
    }

    func testBackspaceCanFullyUnwindParenthesizedExpression() {
        let viewModel = CalculatorViewModel()

        enter("9", into: viewModel)
        viewModel.setOperator(.multiply)
        viewModel.inputParentheses()
        enter("3", into: viewModel)
        viewModel.setOperator(.add)
        enter("1", into: viewModel)

        viewModel.backspace()
        XCTAssertEqual(viewModel.display, "")
        XCTAssertEqual(viewModel.expressionDisplay, "9 × ( 3 +")

        viewModel.backspace()
        XCTAssertEqual(viewModel.display, "3")
        XCTAssertEqual(viewModel.expressionDisplay, "9 × ( 3")

        viewModel.backspace()
        XCTAssertEqual(viewModel.display, "")
        XCTAssertEqual(viewModel.expressionDisplay, "9 × ( 3")

        viewModel.backspace()
        XCTAssertEqual(viewModel.display, "")
        XCTAssertEqual(viewModel.expressionDisplay, "9 × (")

        viewModel.backspace()
        XCTAssertEqual(viewModel.display, "")
        XCTAssertEqual(viewModel.expressionDisplay, "9 ×")

        viewModel.backspace()
        XCTAssertEqual(viewModel.display, "9")
        XCTAssertEqual(viewModel.expressionDisplay, "")

        viewModel.backspace()
        XCTAssertEqual(viewModel.display, "0")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertTrue(viewModel.shouldShowAllClearButton)
    }

    func testPasteAfterPendingClearShowsPastedValue() {
        let viewModel = CalculatorViewModel()

        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.clearEntry()

        pasteString("7", into: viewModel)

        XCTAssertEqual(viewModel.display, "7")
        XCTAssertEqual(viewModel.expressionDisplay, "5 + 7")
    }

    func testClearParenthesizedExpressionKeepsBalancedParenthesisDepth() {
        let viewModel = CalculatorViewModel()

        enter("2", into: viewModel)
        viewModel.setOperator(.add)
        viewModel.inputParentheses()
        enter("3", into: viewModel)
        viewModel.setOperator(.add)
        enter("4", into: viewModel)
        viewModel.inputParenthesis(")")
        viewModel.setOperator(.multiply)
        viewModel.inputParentheses()
        enter("5", into: viewModel)
        viewModel.setOperator(.add)
        enter("1", into: viewModel)

        viewModel.clearEntry()
        enter("6", into: viewModel)
        viewModel.inputParenthesis(")")

        XCTAssertEqual(viewModel.expressionDisplay, "2 + ( 3 + 4 ) × 6")
    }

    func testDisplayEditCursorCanInsertDigitInsideGroupedDisplay() {
        let viewModel = CalculatorViewModel()

        enter("1234", into: viewModel)
        viewModel.setDisplayEditCursor(displayBoundaryIndex: 3)
        viewModel.inputDigit("9")

        XCTAssertEqual(viewModel.display, "12,934")
        XCTAssertEqual(viewModel.displayEditCaretBoundaryIndex, 4)
    }

    func testDisplayEditCursorBackspaceRemovesDigitBeforeCursor() {
        let viewModel = CalculatorViewModel()

        enter("1234", into: viewModel)
        viewModel.setDisplayEditCursor(displayBoundaryIndex: 3)
        viewModel.backspace()

        XCTAssertEqual(viewModel.display, "134")
        XCTAssertEqual(viewModel.displayEditCaretBoundaryIndex, 1)
    }

    func testDisplayEditCursorCanInsertDecimalWithinCurrentInput() {
        let viewModel = CalculatorViewModel()

        enter("12", into: viewModel)
        viewModel.setDisplayEditCursor(displayBoundaryIndex: 1)
        viewModel.inputDecimal()

        XCTAssertEqual(viewModel.display, "1.2")
        XCTAssertEqual(viewModel.displayEditCaretBoundaryIndex, 2)
    }

    func testDisplayEditCursorCanModifyEvaluatedResult() {
        let viewModel = CalculatorViewModel()

        enter("12", into: viewModel)
        viewModel.setOperator(.add)
        enter("3", into: viewModel)
        viewModel.evaluate()

        viewModel.setDisplayEditCursor(displayBoundaryIndex: 1)
        viewModel.inputDigit("9")

        XCTAssertEqual(viewModel.display, "195")
        XCTAssertEqual(viewModel.expressionDisplay, "")
        XCTAssertEqual(viewModel.displayEditCaretBoundaryIndex, 2)

        viewModel.clearDisplayEditCursor()
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "195")
        XCTAssertEqual(viewModel.expressionDisplay, "195 =")
    }

    func testDisplayEditCursorNormalizesGroupedCurrentInputBeforeInsertion() {
        let viewModel = CalculatorViewModel()

        enter("1234", into: viewModel)
        viewModel.setOperator(.add)
        enter("1", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "1,235")

        let insertionBoundary = max(Array(viewModel.display).count - 1, 0)
        viewModel.setDisplayEditCursor(displayBoundaryIndex: insertionBoundary)
        viewModel.inputDigit("9")

        XCTAssertEqual(viewModel.display, "12,395")
        XCTAssertEqual(viewModel.displayEditCaretBoundaryIndex, insertionBoundary + 1)
    }

    func testDisplayEditCursorLeftArrowMovesCaretLeftFromTrailingEdge() {
        let viewModel = CalculatorViewModel()

        enter("1234", into: viewModel)

        XCTAssertTrue(viewModel.moveDisplayEditCursorLeft())
        XCTAssertEqual(viewModel.displayEditCaretBoundaryIndex, 4)
        XCTAssertTrue(viewModel.moveDisplayEditCursorLeft())
        XCTAssertEqual(viewModel.displayEditCaretBoundaryIndex, 3)
    }

    func testDisplayEditCursorRightArrowMovesCaretRightAndReachesTrailingEdge() {
        let viewModel = CalculatorViewModel()

        enter("1234", into: viewModel)
        viewModel.setDisplayEditCursor(displayBoundaryIndex: 3)

        XCTAssertTrue(viewModel.moveDisplayEditCursorRight())
        XCTAssertEqual(viewModel.displayEditCaretBoundaryIndex, 4)
        XCTAssertTrue(viewModel.moveDisplayEditCursorRight())
        XCTAssertEqual(viewModel.displayEditCaretBoundaryIndex, 5)
    }

    func testDisplayEditCursorCanModifyPendingOperationLeftOperand() {
        let viewModel = CalculatorViewModel()

        enter("1234", into: viewModel)
        viewModel.setOperator(.add)

        XCTAssertTrue(viewModel.canDirectlyEditDisplay)

        viewModel.setDisplayEditCursor(displayBoundaryIndex: 2)
        viewModel.inputDigit("9")

        XCTAssertEqual(viewModel.display, "19,234")
        XCTAssertEqual(viewModel.expressionDisplay, "19,234 +")

        viewModel.clearDisplayEditCursor()
        enter("5", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.display, "19,239")
    }

    func testDisplayEditCursorCanModifyOperandInsideParenthesesExpressionMode() {
        let viewModel = CalculatorViewModel()

        viewModel.inputParenthesis("(")
        enter("1234", into: viewModel)

        XCTAssertTrue(viewModel.canDirectlyEditDisplay)

        viewModel.setDisplayEditCursor(displayBoundaryIndex: 3)
        viewModel.inputDigit("9")

        XCTAssertEqual(viewModel.display, "12,934")
        XCTAssertEqual(viewModel.expressionDisplay, "( 12,934")
        XCTAssertEqual(viewModel.displayEditCaretBoundaryIndex, 4)
    }

    func testSetOperatorExitsDisplayEditModeAndStartsFreshPendingOperand() {
        let viewModel = CalculatorViewModel()

        enter("1234", into: viewModel)
        viewModel.setDisplayEditCursor(displayBoundaryIndex: 3)
        viewModel.inputDigit("9")

        XCTAssertEqual(viewModel.display, "12,934")
        XCTAssertNotNil(viewModel.displayEditCaretBoundaryIndex)

        viewModel.setOperator(.add)

        XCTAssertNil(viewModel.displayEditCaretBoundaryIndex)
        XCTAssertEqual(viewModel.expressionDisplay, "12,934 +")

        enter("5", into: viewModel)
        XCTAssertEqual(viewModel.display, "5")
        XCTAssertEqual(viewModel.expressionDisplay, "12,934 + 5")

        viewModel.evaluate()
        XCTAssertEqual(viewModel.display, "12,939")
    }

    func testDisplayEditCursorIgnoresGroupingSeparatorsAcrossSupportedNumberStyles() {
        let styles: [NumberFormatStyle] = [.western, .european, .french, .swiss, .indian]

        for style in styles {
            let viewModel = CalculatorViewModel(numberFormatStyle: style)

            enter("58544", into: viewModel)
            viewModel.inputDecimal()
            enter("545", into: viewModel)

            let displayCharacters = Array(viewModel.display)
            let groupingCharacterIndex = displayCharacters.firstIndex(where: { style.groupingSeparatorCharacters.contains($0) })
            XCTAssertNotNil(groupingCharacterIndex, "Expected grouped display output for \(style)")

            if let groupingCharacterIndex {
                viewModel.setDisplayEditCursor(displayBoundaryIndex: groupingCharacterIndex + 1)
                XCTAssertEqual(viewModel.displayEditCaretBoundaryIndex, groupingCharacterIndex, "Grouping separator should collapse to the preceding digit boundary for \(style)")
            }

            let decimalCharacterIndex = displayCharacters.firstIndex(where: { String($0) == style.decimalSeparator })
            XCTAssertNotNil(decimalCharacterIndex, "Expected decimal separator in display output for \(style)")

            if let decimalCharacterIndex {
                viewModel.setDisplayEditCursor(displayBoundaryIndex: decimalCharacterIndex + 1)
                XCTAssertEqual(viewModel.displayEditCaretBoundaryIndex, decimalCharacterIndex + 1, "Decimal separator should remain selectable for \(style)")
            }
        }
    }

    func testEditableDisplayLayoutScalesLongNumbersToFitAvailableWidth() {
        let layout = EditableDisplayResultTextLayout(
            text: "12,345,678,901,234,567",
            fontSize: 56,
            availableWidth: 240,
            minScaleFactor: 0.22
        )

        XCTAssertLessThan(layout.resolvedFontSize, 56)
        XCTAssertLessThanOrEqual(layout.textWidth, 240.5)
        XCTAssertLessThanOrEqual(layout.boundaryXPositions.last ?? 0, 240.5)
    }

    func testEditableDisplayLayoutRescalesWhenDigitCountChanges() {
        let shorter = EditableDisplayResultTextLayout(
            text: "1,234,567",
            fontSize: 56,
            availableWidth: 240,
            minScaleFactor: 0.22
        )
        let longer = EditableDisplayResultTextLayout(
            text: "12,345,678,901,234,567",
            fontSize: 56,
            availableWidth: 240,
            minScaleFactor: 0.22
        )

        XCTAssertGreaterThan(shorter.resolvedFontSize, longer.resolvedFontSize)
        XCTAssertGreaterThan(shorter.caretWidth, longer.caretWidth)
        XCTAssertGreaterThan(shorter.caretHeight, longer.caretHeight)
        XCTAssertGreaterThan(shorter.caretTopInset, longer.caretTopInset)
        XCTAssertLessThanOrEqual(longer.textWidth, 240.5)
        XCTAssertLessThanOrEqual(longer.boundaryXPositions.last ?? 0, 240.5)
    }
}
