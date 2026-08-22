import XCTest
@testable import EnterCalcCore

/// Currency mode is derived state: the calculator is in it exactly when a
/// currency symbol is showing, so these cover entering and leaving it.
final class CurrencyModeTests: XCTestCase {
    private func enter(_ digits: String, into viewModel: CalculatorViewModel) {
        for character in digits {
            if character == "." {
                viewModel.inputDecimal()
            } else {
                viewModel.inputDigit(String(character))
            }
        }
    }

    func testTogglingOnEntersCurrencyMode() {
        let viewModel = CalculatorViewModel()
        enter("12", into: viewModel)

        viewModel.toggleCurrencySymbol("£")

        XCTAssertEqual(viewModel.activeCurrencySymbol, "£")
        XCTAssertTrue(viewModel.display.contains("£"))
    }

    func testTogglingOffLeavesCurrencyModeAndDropsTheSymbol() {
        let viewModel = CalculatorViewModel()
        enter("12", into: viewModel)
        viewModel.toggleCurrencySymbol("£")

        viewModel.toggleCurrencySymbol("£")

        XCTAssertNil(viewModel.activeCurrencySymbol)
        XCTAssertFalse(viewModel.display.contains("£"))
    }

    // The entered number is a separate concern from how it is labelled, so
    // leaving currency mode must not disturb it.
    func testTogglingOffPreservesTheEnteredValue() {
        let viewModel = CalculatorViewModel()
        enter("12.50", into: viewModel)
        viewModel.toggleCurrencySymbol("$")

        viewModel.toggleCurrencySymbol("$")

        XCTAssertEqual(viewModel.display, "12.5")
    }

    // The key is the way out of currency mode however it was entered — including
    // a symbol typed on a hardware keyboard that differs from the configured one.
    func testTogglingClearsASymbolThatDiffersFromTheConfiguredOne() {
        let viewModel = CalculatorViewModel()
        enter("5", into: viewModel)
        viewModel.inputCurrencySymbol("€")

        viewModel.toggleCurrencySymbol("$")

        XCTAssertNil(viewModel.activeCurrencySymbol)
    }

    func testClearingWithoutAnActiveSymbolIsANoOp() {
        let viewModel = CalculatorViewModel()
        enter("7", into: viewModel)

        viewModel.clearCurrencySymbol()

        XCTAssertNil(viewModel.activeCurrencySymbol)
        XCTAssertEqual(viewModel.display, "7")
    }

    func testTogglingCurrencyIsUndoable() {
        let viewModel = CalculatorViewModel()
        enter("40", into: viewModel)
        viewModel.toggleCurrencySymbol("$")
        XCTAssertEqual(viewModel.activeCurrencySymbol, "$")

        viewModel.toggleCurrencySymbol("$")
        XCTAssertNil(viewModel.activeCurrencySymbol)

        viewModel.undo()

        XCTAssertEqual(viewModel.activeCurrencySymbol, "$")
    }

    func testCurrencyModeSurvivesArithmetic() {
        let viewModel = CalculatorViewModel()
        enter("10", into: viewModel)
        viewModel.toggleCurrencySymbol("$")
        viewModel.setOperator(.add)
        enter("5", into: viewModel)
        viewModel.evaluate()

        XCTAssertEqual(viewModel.activeCurrencySymbol, "$")
        XCTAssertTrue(viewModel.display.contains("$"), "expected currency in \(viewModel.display)")
    }
}
