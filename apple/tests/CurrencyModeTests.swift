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

    // MARK: - Editing caret (#118)

    /// The display with a `|` where the caret is drawn, so a failure reads as
    /// the misplacement itself.
    private func caretRendering(of viewModel: CalculatorViewModel) -> String {
        let characters = Array(viewModel.display)
        guard let boundary = viewModel.displayEditCaretBoundaryIndex else { return viewModel.display }
        return String(characters[..<boundary]) + "|" + String(characters[boundary...])
    }

    private func currencyViewModel(_ digits: String, symbol: String, negative: Bool = false, style: NumberFormatStyle? = nil) -> CalculatorViewModel {
        let viewModel = CalculatorViewModel()
        if let style { viewModel.setNumberFormatStyle(style) }
        enter(digits, into: viewModel)
        if negative { viewModel.toggleSign() }
        viewModel.toggleCurrencySymbol(symbol)
        return viewModel
    }

    // Tapping at the very start of the display must put the caret after the
    // symbol, before the first digit: the symbol is not something you edit.
    func testTappingTheStartOfTheDisplayPutsTheCaretAfterTheSymbol() {
        let dollars = currencyViewModel("120", symbol: "$")
        dollars.setDisplayEditCursor(displayBoundaryIndex: 0)
        XCTAssertEqual(caretRendering(of: dollars), "$|120")

        let euros = currencyViewModel("1234", symbol: "€", style: .western)
        euros.setDisplayEditCursor(displayBoundaryIndex: 0)
        XCTAssertEqual(caretRendering(of: euros), "€|1,234")
    }

    // Symbols accepted from a hardware keyboard go beyond the Settings
    // picker's catalog, and must be stepped over just the same.
    func testSymbolsOutsideTheCatalogAlsoKeepTheCaretAfterThem() {
        for symbol in ["₿", "₤"] {
            XCTAssertNil(CurrencyCatalog.option(forSymbol: symbol), "\(symbol) is in the catalog now; pick another")
            let viewModel = currencyViewModel("120", symbol: symbol)
            viewModel.setDisplayEditCursor(displayBoundaryIndex: 0)
            XCTAssertEqual(caretRendering(of: viewModel), "\(symbol)|120")
        }
    }

    func testTappingJustAfterTheSymbolPutsTheCaretAfterIt() {
        let viewModel = currencyViewModel("120", symbol: "£")
        viewModel.setDisplayEditCursor(displayBoundaryIndex: 1)
        XCTAssertEqual(caretRendering(of: viewModel), "£|120")
    }

    func testMovingLeftStopsAfterTheSymbol() {
        let viewModel = currencyViewModel("120", symbol: "$")
        viewModel.setDisplayEditCursor(displayBoundaryIndex: Array(viewModel.display).count)
        for _ in 0..<6 { viewModel.moveDisplayEditCursorLeft() }
        XCTAssertEqual(caretRendering(of: viewModel), "$|120")
    }

    func testNegativeAmountPutsTheCaretAfterTheSignAndSymbol() {
        let viewModel = currencyViewModel("120", symbol: "$", negative: true)
        viewModel.setDisplayEditCursor(displayBoundaryIndex: 0)
        XCTAssertEqual(caretRendering(of: viewModel), "-$|120")
    }

    // Grouping separators are still skipped the other way: the caret sits
    // right after the digit it follows, not after the separator.
    func testCaretStillStopsBeforeAGroupingSeparator() {
        let viewModel = currencyViewModel("1234", symbol: "$", style: .western)
        viewModel.setDisplayEditCursor(displayBoundaryIndex: 2)
        XCTAssertEqual(caretRendering(of: viewModel), "$1|,234")
    }

    // A digit typed at the leftmost caret position goes in front of the
    // first digit, behind the symbol.
    func testTypingAtTheLeftmostCaretInsertsAfterTheSymbol() {
        let viewModel = currencyViewModel("120", symbol: "$")
        viewModel.setDisplayEditCursor(displayBoundaryIndex: 0)
        viewModel.inputDigit("5")
        XCTAssertEqual(viewModel.display, "$5,120")
        XCTAssertEqual(caretRendering(of: viewModel), "$5|,120")
    }

    // MARK: - Live VAT and Tip (#124)

    // Opening a panel writes its result straight away; changing the rate
    // replaces it rather than stacking, and one undo returns to the amount the
    // panel started from.
    func testLiveToolResultReplacesItselfAndUndoesInOneStep() {
        let viewModel = currencyViewModel("100", symbol: "€")
        let base = viewModel.toolBase(for: .vat)
        XCTAssertEqual(base, 100)

        viewModel.applyLiveToolResult(119, tool: .vat, base: base, describedBy: "Add VAT 19% =")
        XCTAssertEqual(viewModel.currentValue, 119)
        XCTAssertEqual(viewModel.toolBase(for: .vat), 100, "reopening works from the original amount")

        viewModel.applyLiveToolResult(107, tool: .vat, base: base, describedBy: "Add VAT 7% =")
        XCTAssertEqual(viewModel.currentValue, 107)

        viewModel.undo()
        XCTAssertEqual(viewModel.currentValue, 100, "one undo step for the whole adjustment")
    }

    // Another tool, or anything typed after the result, starts from what is
    // on the display.
    func testToolBaseFollowsTheDisplayOnceSomethingElseHappens() {
        let viewModel = currencyViewModel("100", symbol: "€")
        viewModel.applyLiveToolResult(119, tool: .vat, base: 100, describedBy: "Add VAT 19% =")

        XCTAssertEqual(viewModel.toolBase(for: .tip), 119, "tipping on a VAT-inclusive price")

        viewModel.inputDigit("5")
        XCTAssertEqual(viewModel.toolBase(for: .vat), viewModel.currentValue)
        XCTAssertEqual(viewModel.currentValue, 5)
    }

    // The trash button restores the display exactly as it was before the
    // panel opened, and does nothing for a tool that isn't on the display.
    func testRemovingALiveToolResultRestoresTheOriginal() {
        let viewModel = currencyViewModel("100", symbol: "€")
        viewModel.applyLiveToolResult(119, tool: .vat, base: 100, describedBy: "Add VAT 19% =")
        viewModel.applyLiveToolResult(107, tool: .vat, base: 100, describedBy: "Add VAT 7% =")

        viewModel.removeLiveToolResult(.tip)
        XCTAssertEqual(viewModel.currentValue, 107, "Tip's trash leaves VAT alone")

        viewModel.removeLiveToolResult(.vat)
        XCTAssertEqual(viewModel.currentValue, 100)
        XCTAssertEqual(viewModel.toolBase(for: .vat), 100)
    }

    // VAT and Tip amounts show full cents, trailing zeros kept, in the active
    // number format, and none for the yen.
    func testCurrencyAmountsShowTheCurrencysFullDecimals() {
        let pounds = currencyViewModel("1", symbol: "£")
        XCTAssertEqual(pounds.formattedCurrencyAmount(Decimal(string: "125.5")!, fractionDigits: 2), "£125.50")
        XCTAssertEqual(pounds.formattedCurrencyAmount(1234, fractionDigits: 2), "£1,234.00")
        XCTAssertEqual(pounds.formattedCurrencyAmount(Decimal(string: "0.005")!, fractionDigits: 2), "£0.01")

        let euros = currencyViewModel("1", symbol: "€", style: .european)
        XCTAssertEqual(euros.formattedCurrencyAmount(Decimal(string: "1234.5")!, fractionDigits: 2), "€1.234,50")

        let yen = currencyViewModel("1", symbol: "¥")
        XCTAssertEqual(yen.formattedCurrencyAmount(Decimal(string: "909.09")!, fractionDigits: 0), "¥909")
    }

    func testTipIsRoundedToTheCurrency() {
        XCTAssertEqual(TipBreakdown.roundedTip(bill: Decimal(string: "33.33")!, rate: 15, scale: 2), Decimal(string: "5"))
        XCTAssertEqual(TipBreakdown.roundedTip(bill: Decimal(string: "47.10")!, rate: 18, scale: 2), Decimal(string: "8.48"))
        XCTAssertEqual(TipBreakdown.roundedTip(bill: 1234, rate: 15, scale: 0), 185)
    }

    // The operation line starts from the amount the tool worked from.
    func testToolOperationLineShowsTheOriginalAmount() {
        let dollars = currencyViewModel("100", symbol: "$")
        XCTAssertEqual(dollars.toolOperationLine(base: 100, label: "VAT", rate: 10), "$100 + VAT(10%) =")
        XCTAssertEqual(dollars.toolOperationLine(base: 110, label: "VAT", rate: 10, isRemoving: true), "$110 − VAT(10%) =")
        XCTAssertEqual(dollars.toolOperationLine(base: 1234, label: "TIP", rate: Decimal(string: "17.5")!), "$1,234 + TIP(17.5%) =")
    }

    // Moving the Tip slider to Off leaves the amount on its own: no operation
    // line, even one the amount had before the tip (here "50 + 50 =").
    func testTipOffClearsTheOperationLine() {
        let viewModel = currencyViewModel("50", symbol: "$")
        viewModel.setOperator(.add)
        enter("50", into: viewModel)
        viewModel.evaluate()
        XCTAssertFalse(viewModel.expressionDisplay.isEmpty)

        viewModel.applyLiveToolResult(118, tool: .tip, base: 100, describedBy: "100 + TIP(18%) =")
        viewModel.removeLiveToolResult(.tip, clearingOperationLine: true)

        XCTAssertEqual(viewModel.currentValue, 100)
        XCTAssertEqual(viewModel.expressionDisplay, "")
    }

    // The pane can open at 0% (Off), so no tip was applied: Off still clears
    // the operation line and leaves the amount alone.
    func testTipOffClearsTheOperationLineEvenWithoutATip() {
        let viewModel = currencyViewModel("50", symbol: "$")
        viewModel.setOperator(.add)
        enter("50", into: viewModel)
        viewModel.evaluate()

        viewModel.removeLiveToolResult(.tip, clearingOperationLine: true)

        XCTAssertEqual(viewModel.currentValue, 100)
        XCTAssertEqual(viewModel.expressionDisplay, "")
    }

    func testOperationLineRoundsTheRateForDisplayOnly() {
        let dollars = currencyViewModel("100", symbol: "$")
        XCTAssertEqual(dollars.toolOperationLine(base: 100, label: "VAT", rate: Decimal(string: "12.34567")!), "$100 + VAT(12.346%) =")
    }
}
