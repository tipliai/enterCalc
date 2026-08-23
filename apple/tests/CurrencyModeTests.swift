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

    // Currency mode is a mode the user switched on, not part of the calculation,
    // so clearing the entry must not silently drop it.
    func testCurrencyModeSurvivesAllClear() {
        let viewModel = CalculatorViewModel()
        enter("40", into: viewModel)
        viewModel.toggleCurrencySymbol("$")

        viewModel.clearAll()

        XCTAssertEqual(viewModel.activeCurrencySymbol, "$")
        enter("7", into: viewModel)
        XCTAssertTrue(viewModel.display.contains("$"), "expected currency in \(viewModel.display)")
    }

    // The key stays the only way out, so it must still work after a clear.
    func testCurrencyModeCanBeTurnedOffAfterAllClear() {
        let viewModel = CalculatorViewModel()
        enter("40", into: viewModel)
        viewModel.toggleCurrencySymbol("$")
        viewModel.clearAll()

        viewModel.toggleCurrencySymbol("$")

        XCTAssertNil(viewModel.activeCurrencySymbol)
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

    // MARK: - The symbol is visible whenever currency mode is on

    // Pressing the currency key with nothing entered has to show "$0", not a
    // bare "0" — otherwise the only sign the mode is on is the label, and the
    // key looks like it did nothing.
    func testCurrencyOnAnUntouchedZeroShowsTheSymbol() {
        let viewModel = CalculatorViewModel()
        viewModel.toggleCurrencySymbol("$")

        XCTAssertEqual(viewModel.display, "$0")
    }

    func testCurrencyOnATypedZeroShowsTheSymbol() {
        let viewModel = CalculatorViewModel()
        enter("0", into: viewModel)
        viewModel.toggleCurrencySymbol("$")

        XCTAssertEqual(viewModel.display, "$0")
    }

    // All Clear keeps currency mode on, so the zero it leaves behind has to
    // keep the symbol too.
    func testAllClearLeavesTheSymbolOnTheZero() {
        let viewModel = CalculatorViewModel()
        viewModel.toggleCurrencySymbol("$")
        enter("12", into: viewModel)
        viewModel.clearAll()

        XCTAssertEqual(viewModel.activeCurrencySymbol, "$")
        XCTAssertEqual(viewModel.display, "$0")
    }

    // Sweeps the states a value can be in and asserts the symbol is on screen
    // in every one of them. Percent is excluded deliberately: the result is a
    // ratio rather than an amount, so it drops the symbol on purpose.
    func testSymbolStaysVisibleAcrossValueStates() {
        let cases: [(String, (CalculatorViewModel) -> Void)] = [
            ("nothing entered", { _ in }),
            ("typed zero", { $0.inputDigit("0") }),
            ("typed value", { $0.inputDigit("1"); $0.inputDigit("2") }),
            ("after all clear", { $0.inputDigit("1"); $0.clearAll() }),
            ("pending operator", { $0.inputDigit("5"); $0.setOperator(.add) }),
            ("after evaluate", { vm in
                vm.inputDigit("1"); vm.setOperator(.add); vm.inputDigit("2"); vm.evaluate()
            }),
            ("after backspace to empty", { $0.inputDigit("7"); $0.backspace() }),
            ("after sign toggle", { $0.inputDigit("5"); $0.toggleSign() }),
            ("after square", { $0.inputDigit("3"); $0.square() }),
            ("after undo", { $0.inputDigit("9"); $0.undo() })
        ]

        for (name, steps) in cases {
            let viewModel = CalculatorViewModel()
            viewModel.toggleCurrencySymbol("$")
            steps(viewModel)

            XCTAssertEqual(viewModel.activeCurrencySymbol, "$", "currency mode lost: \(name)")
            XCTAssertTrue(
                viewModel.display.contains("$"),
                "expected the symbol in \(name), got \(viewModel.display)"
            )
        }
    }

    // The configured symbol is whatever the user picked, so the check above
    // must not be quietly specific to the dollar sign.
    func testSymbolStaysVisibleForOtherCurrencies() {
        for symbol in ["€", "£", "¥", "₹"] {
            let viewModel = CalculatorViewModel()
            viewModel.toggleCurrencySymbol(symbol)

            XCTAssertEqual(viewModel.display, "\(symbol)0", "wrong display for \(symbol)")
        }
    }
}
