import XCTest
@testable import EnterCalcCore

final class DisplaySpeechTests: XCTestCase {
    private let words: [String: String] = [
        "a11y.display.completed": "%1$@, from %2$@",
        "a11y.display.pending": "%1$@, after %2$@",
        "a11y.operator.plus": "plus",
        "a11y.operator.minus": "minus",
        "a11y.operator.times": "times",
        "a11y.operator.dividedBy": "divided by",
        "a11y.operator.equals": "equals",
        "a11y.operator.approximately": "approximately",
        "a11y.operator.percent": "percent",
        "a11y.operator.squareRoot": "square root of",
        "a11y.announce.result": "Equals %@",
        "a11y.announce.cleared": "Cleared",
        "a11y.key.point": "point",
        "a11y.number.repeating": "repeating",
        "a11y.announce.screen": "Screen %1$@, %2$@ shown",
        "a11y.announce.window": "Window %1$@, %2$@ shown",
        "a11y.currency.cent": "1 cent",
        "a11y.currency.cents": "%@ cents",
        "a11y.currency.penny": "1 penny",
        "a11y.currency.pence": "%@ pence",
        "a11y.announce.action": "%1$@, %2$@ displayed",
        "a11y.key.clear": "Clear entry",
        "a11y.key.parentheses": "parentheses",
        "a11y.key.openParenthesis": "open parenthesis",
        "a11y.key.closeParenthesis": "close parenthesis"
    ]

    private func localize(_ key: String) -> String {
        words[key] ?? key
    }

    private func state(
        _ display: String,
        _ operation: String = "",
        error: Bool = false,
        count: Int = 0
    ) -> DisplaySpeech.State {
        DisplaySpeech.State(display: display, operation: operation, isError: error, completedCalculations: count)
    }

    func testOperatorsAreSpokenAsWords() {
        XCTAssertEqual(DisplaySpeech.spoken("5 + 7 =", localize: localize), "5 plus 7 equals")
        XCTAssertEqual(DisplaySpeech.spoken("9 − 2 × 3 ÷ 4", localize: localize), "9 minus 2 times 3 divided by 4")
        XCTAssertEqual(DisplaySpeech.spoken("200 + 15%", localize: localize), "200 plus 15 percent")
        XCTAssertEqual(DisplaySpeech.spoken("√(16)", localize: localize), "square root of (16)")
        XCTAssertEqual(DisplaySpeech.spoken("10 ÷ 3 ≈", localize: localize), "10 divided by 3 approximately")
    }

    // Numbers, separators and currency are left for VoiceOver, which already
    // reads them as amounts.
    func testNumbersAndCurrencyAreLeftAlone() {
        XCTAssertEqual(DisplaySpeech.spoken("$1,234.50", localize: localize), "$1,234.50")
        XCTAssertEqual(DisplaySpeech.spoken("1.234,5 €", decimalSeparator: ",", localize: localize), "1.234,5 €")
    }

    func testAHyphenIsAMinusOnlyWhenItStartsANumber() {
        XCTAssertEqual(DisplaySpeech.spoken("-5", localize: localize), "minus 5")
        XCTAssertEqual(DisplaySpeech.spoken("3 × (-2)", localize: localize), "3 times ( minus 2)")
        XCTAssertEqual(DisplaySpeech.spoken("1.2e-5", localize: localize), "1 point 2 e-5")
    }

    func testAFinishedCalculationReadsTheResultThenWhereItCameFrom() {
        XCTAssertEqual(DisplaySpeech.value(for: state("12", "5 + 7 ="), localize: localize), "12, from 5 plus 7")
    }

    func testAnUnfinishedCalculationReadsTheEntryThenWhatCameBefore() {
        XCTAssertEqual(DisplaySpeech.value(for: state("7", "5 +"), localize: localize), "7, after 5 plus")
    }

    func testAPlainNumberIsReadOnItsOwn() {
        XCTAssertEqual(DisplaySpeech.value(for: state("42"), localize: localize), "42")
    }

    func testAnErrorIsReadAsTheMessage() {
        let value = DisplaySpeech.value(for: state("Cannot divide by zero", "1 ÷ 0 =", error: true), localize: localize)
        XCTAssertEqual(value, "Cannot divide by zero")
    }

    func testFinishingACalculationAnnouncesTheResult() {
        let before = state("7", "5 +", count: 3)
        let after = state("12", "5 + 7 =", count: 4)
        let announcement = DisplaySpeech.announcement(from: before, to: after, localize: localize)
        XCTAssertEqual(announcement, .result("12"))
        XCTAssertEqual(DisplaySpeech.text(for: announcement!, localize: localize), "Equals 12")
    }

    func testAnErrorIsAnnounced() {
        let before = state("0", "1 ÷", count: 3)
        let after = state("Cannot divide by zero", "1 ÷ 0 =", error: true, count: 3)
        XCTAssertEqual(
            DisplaySpeech.announcement(from: before, to: after, localize: localize),
            .error("Cannot divide by zero")
        )
    }

    // AC is announced from the clear itself, so it is heard even when only a
    // blank entry was on screen (42, C, then AC).
    func testAllClearIsAnnounced() {
        var before = state("12", "5 + 7 =", count: 4)
        var after = state("0", count: 4)
        after.allClearCount = 1
        let announcement = DisplaySpeech.announcement(from: before, to: after, localize: localize)
        XCTAssertEqual(announcement, .cleared)
        XCTAssertEqual(DisplaySpeech.text(for: announcement!, localize: localize), "Cleared")

        before = state("0")
        after = state("0")
        after.allClearCount = 1
        XCTAssertEqual(DisplaySpeech.announcement(from: before, to: after, localize: localize), .cleared)

        let viewModel = CalculatorViewModel()
        viewModel.inputDigit("4")
        viewModel.inputDigit("2")
        viewModel.clearEntry()
        let blank = viewModel.displaySpeechState
        viewModel.clearAll()
        XCTAssertEqual(DisplaySpeech.announcement(from: blank, to: viewModel.displaySpeechState, localize: localize), .cleared)
    }

    // Typing is already spoken by the key that was pressed; repeating it as an
    // announcement would talk over it.
    func testTypingIsNotAnnounced() {
        XCTAssertNil(DisplaySpeech.announcement(from: state("1"), to: state("12"), localize: localize))
        XCTAssertNil(DisplaySpeech.announcement(from: state("12"), to: state("12", "12 +"), localize: localize))
        // Backspacing a lone number to zero is editing, not clearing.
        XCTAssertNil(DisplaySpeech.announcement(from: state("5"), to: state("0"), localize: localize))
    }

    // A long decimal read as one number comes out as "9 point 3 hundred
    // trillion..."; each decimal digit is read on its own instead, and a run
    // of one digit is read three times and then "repeating".
    func testRepeatingDecimalsAreReadThreeTimesThenRepeating() {
        XCTAssertEqual(DisplaySpeech.spoken("9.333333333333333", isRoundedResult: true, localize: localize), "9 point 3 3 3 repeating")
        XCTAssertEqual(DisplaySpeech.spoken("0.6666666666666667", isRoundedResult: true, localize: localize), "0 point 6 6 6 repeating")
        XCTAssertEqual(DisplaySpeech.spoken("1.833333333333333", isRoundedResult: true, localize: localize), "1 point 8 3 3 3 repeating")
        XCTAssertEqual(DisplaySpeech.spoken("0.1666666666666667", isRoundedResult: true, localize: localize), "0 point 1 6 6 6 repeating")
    }

    // "Repeating" is only for a number cut off at the display's 16 digits.
    // Anything shorter is exact, so every digit is read; so is a full-length
    // one whose last digit is not the run's, rounded or not.
    func testOnlyACutOffRunIsRepeating() {
        // A full-length number that was typed, not rounded, is exact.
        XCTAssertEqual(
            DisplaySpeech.spoken("1.222222222222222", localize: localize),
            "1 point 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2"
        )
        // A run of zeros never hides the digit after it.
        XCTAssertEqual(
            DisplaySpeech.spoken("1.000000000000001", isRoundedResult: true, localize: localize),
            "1 point 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1"
        )
        XCTAssertEqual(DisplaySpeech.spoken("3.2222225", localize: localize), "3 point 2 2 2 2 2 2 5")
        XCTAssertEqual(DisplaySpeech.spoken("3.2222222", localize: localize), "3 point 2 2 2 2 2 2 2")
        XCTAssertEqual(DisplaySpeech.spoken("1.8333333333", localize: localize), "1 point 8 3 3 3 3 3 3 3 3 3")
        XCTAssertEqual(
            DisplaySpeech.spoken("3.222222222222225", localize: localize),
            "3 point 2 2 2 2 2 2 2 2 2 2 2 2 2 2 5"
        )
    }

    // Exactly three of a digit is all there is, so nothing is left out and
    // "repeating" would be wrong.
    func testThreeOfADigitAtTheEndIsJustRead() {
        XCTAssertEqual(DisplaySpeech.spoken("2.5333", localize: localize), "2 point 5 3 3 3")
        XCTAssertEqual(DisplaySpeech.spoken("1.0005", localize: localize), "1 point 0 0 0 5")
    }

    func testEveryDecimalDigitIsReadOnItsOwn() {
        XCTAssertEqual(DisplaySpeech.spoken("3.14159265", localize: localize), "3 point 1 4 1 5 9 2 6 5")
        XCTAssertEqual(DisplaySpeech.spoken("2.5", localize: localize), "2 point 5")
        XCTAssertEqual(DisplaySpeech.spoken("0.142857142857", localize: localize), "0 point 1 4 2 8 5 7 1 4 2 8 5 7")
    }

    // The whole part stays one number, read by VoiceOver as it is written.
    func testTheWholePartIsReadAsANumber() {
        XCTAssertEqual(DisplaySpeech.spoken("1,234.56", localize: localize), "1,234 point 5 6")
        XCTAssertEqual(DisplaySpeech.spoken("1,234", localize: localize), "1,234")
    }

    // An amount with more decimals than cents is read digit by digit, not
    // as "81 dollars, 2 million...".
    func testLongCurrencyDecimalsAreReadDigitByDigit() {
        XCTAssertEqual(DisplaySpeech.spoken("$81.2154789", localize: localize), "$81 point 2 1 5 4 7 8 9")
        XCTAssertEqual(DisplaySpeech.spoken("$3.333333333333333", isRoundedResult: true, localize: localize), "$3 point 3 3 3 repeating")
        XCTAssertEqual(DisplaySpeech.spoken("$3.3333333", localize: localize), "$3 point 3 3 3 3 3 3 3")
    }

    // Amounts keep their currency reading: "$9.50" is nine dollars fifty.
    func testCurrencyAmountsAreLeftAlone() {
        XCTAssertEqual(DisplaySpeech.spoken("$9.50", localize: localize), "$9.50")
        XCTAssertEqual(DisplaySpeech.spoken("9,50 €", decimalSeparator: ",", localize: localize), "9,50 €")
    }

    // Under one unit, an amount is its cents: "71 cents", not "zero dollars
    // point seven one".
    func testAmountsUnderOneAreReadAsCents() {
        XCTAssertEqual(DisplaySpeech.spoken("$0.71", localize: localize), "71 cents")
        XCTAssertEqual(DisplaySpeech.spoken("$0.05", localize: localize), "5 cents")
        XCTAssertEqual(DisplaySpeech.spoken("$0.01", localize: localize), "1 cent")
        XCTAssertEqual(DisplaySpeech.spoken("$0.4", localize: localize), "40 cents")
        XCTAssertEqual(DisplaySpeech.spoken("-$0.71", localize: localize), "minus 71 cents")
        XCTAssertEqual(DisplaySpeech.spoken("0,71 €", decimalSeparator: ",", localize: localize), "71 cents")
        XCTAssertEqual(DisplaySpeech.spoken("£0.30", localize: localize), "30 pence")
        XCTAssertEqual(DisplaySpeech.spoken("$0.71 + $1.50", localize: localize), "71 cents plus $1.50")
        // Zero, whole amounts, long decimals and currencies without a word stay as they were.
        XCTAssertEqual(DisplaySpeech.spoken("$0.00", localize: localize), "$0.00")
        XCTAssertEqual(DisplaySpeech.spoken("$1.71", localize: localize), "$1.71")
        XCTAssertEqual(DisplaySpeech.spoken("$0.715", localize: localize), "$0 point 7 1 5")
        XCTAssertEqual(DisplaySpeech.spoken("0.71", localize: localize), "0 point 7 1")
        XCTAssertEqual(DisplaySpeech.spoken("₹0.71", localize: localize), "₹0.71")
    }

    // Panel amounts work out their own decimal separator.
    func testPanelAmountsInferTheirSeparator() {
        XCTAssertEqual(DisplaySpeech.spokenAmount("$0.40", localize: localize), "40 cents")
        XCTAssertEqual(DisplaySpeech.spokenAmount("0,40 €", localize: localize), "40 cents")
        XCTAssertEqual(DisplaySpeech.spokenAmount("1.234,56 €", localize: localize), "1.234,56 €")
        XCTAssertEqual(DisplaySpeech.spokenAmount("$1,234.56", localize: localize), "$1,234.56")
    }

    // The arrow keys move the Tip slider a 2% notch at a time.
    func testTipArrowsStepToTheNextNotch() {
        XCTAssertEqual(TipRateStep.next(after: 16, up: true), 18)
        XCTAssertEqual(TipRateStep.next(after: 16, up: false), 14)
        XCTAssertEqual(TipRateStep.next(after: 15, up: true), 16)
        XCTAssertEqual(TipRateStep.next(after: 15, up: false), 14)
        XCTAssertEqual(TipRateStep.next(after: 2, up: false), 0)
        XCTAssertNil(TipRateStep.next(after: 0, up: false))
        XCTAssertNil(TipRateStep.next(after: 40, up: true))
        XCTAssertNil(TipRateStep.next(after: 45, up: true))
        XCTAssertEqual(TipRateStep.next(after: 45, up: false), 40)
    }

    // In the key chooser the arrows start from the key's current action and
    // stop at the ends of the grid.
    func testChooserArrowsMoveThroughTheOptions() {
        let assignments = CalculatorFunctionKeyAssignments.default
        let slot = CalculatorFunctionSlot.action1
        let current = assignments[slot]
        let options = CalculatorFunctionKey.chooserOrder
        let index = try! XCTUnwrap(options.firstIndex(of: current))
        var session = FunctionKeyChooserSession(slot: slot, anchor: .zero)

        let expectedNext = options.indices.contains(index + 1) ? options[index + 1] : nil
        XCTAssertEqual(session.highlight(movedBy: 1, assignments: assignments), expectedNext)

        session.highlighted = options[0]
        XCTAssertNil(session.highlight(movedBy: -1, assignments: assignments))
        XCTAssertEqual(session.highlight(movedBy: 1, assignments: assignments), options[1])
        session.highlighted = options[options.count - 1]
        XCTAssertNil(session.highlight(movedBy: 1, assignments: assignments))

        let label: (CalculatorFunctionKey) -> String = { $0.rawValue }
        let words = ["a11y.functionKey.current": "%@, current"]
        XCTAssertEqual(
            session.spokenOption(current, assignments: assignments, label: label, localize: { words[$0] ?? $0 }),
            "\(current.rawValue), current"
        )
    }

    // Arriving at another screen or window says which, and what it shows.
    func testScreenAndWindowAnnouncements() {
        XCTAssertEqual(
            DisplaySpeech.instanceAnnouncement(number: 2, isWindow: false, state: state("500.113"), localize: localize),
            "Screen 2, 500 point 1 1 3 shown"
        )
        XCTAssertEqual(
            DisplaySpeech.instanceAnnouncement(number: 1, isWindow: true, state: state("$1.55"), localize: localize),
            "Window 1, $1.55 shown"
        )
        XCTAssertEqual(
            DisplaySpeech.instanceAnnouncement(number: 3, isWindow: true, state: state("$0.71"), localize: localize),
            "Window 3, 71 cents shown"
        )
    }

    // A space between digits groups thousands, as French formatting does, and
    // stays part of the amount: €1 000,50 is not "€1" and "50 cents".
    func testGroupingSpacesStayInTheNumber() {
        XCTAssertEqual(
            DisplaySpeech.spoken("€1\u{202F}000,50", decimalSeparator: ",", localize: localize),
            "€1\u{202F}000,50"
        )
        XCTAssertEqual(DisplaySpeech.spoken("1 000,5", decimalSeparator: ",", localize: localize), "1 000 point 5")
        XCTAssertEqual(DisplaySpeech.spoken("5 + 7", localize: localize), "5 plus 7")
    }

    // With a comma decimal separator, dots are grouping and the comma splits.
    func testACommaDecimalSeparatorIsHonoured() {
        XCTAssertEqual(
            DisplaySpeech.spoken("1.234,333333333333", decimalSeparator: ",", isRoundedResult: true, localize: localize),
            "1.234 point 3 3 3 repeating"
        )
        XCTAssertEqual(DisplaySpeech.spoken("1.234,5", decimalSeparator: ",", localize: localize), "1.234 point 5")
    }

    func testTheAnnouncedResultUsesTheSameReading() {
        let before = DisplaySpeech.State(display: "3", operation: "28 ÷", isError: false, completedCalculations: 0)
        let after = DisplaySpeech.State(
            display: "9.333333333333333", operation: "28 ÷ 3 =", isError: false, completedCalculations: 1, isRoundedResult: true
        )
        XCTAssertEqual(
            DisplaySpeech.announcement(from: before, to: after, localize: localize),
            .result("9 point 3 3 3 repeating")
        )
    }

    // After Undo, Currency and the other action keys, VoiceOver says what the
    // display shows, since the change is otherwise silent.
    func testActionKeysSayWhatIsDisplayed() {
        XCTAssertEqual(DisplaySpeech.actionAnnouncement("Undo", state: state("2", "2 +"), localize: localize), "Undo, 2 displayed")
        XCTAssertEqual(DisplaySpeech.actionAnnouncement("Currency", state: state("$3", "1 + 2 ="), localize: localize), "Currency, $3 displayed")
        XCTAssertEqual(
            DisplaySpeech.actionAnnouncement("Square Root", state: state("1.4142135623"), localize: localize),
            "Square Root, 1 point 4 1 4 2 1 3 5 6 2 3 displayed"
        )
        XCTAssertEqual(
            DisplaySpeech.actionAnnouncement("1/x", state: state("Cannot divide by zero", error: true), localize: localize),
            "1/x, Cannot divide by zero displayed"
        )
    }

    func testKeysAreSpokenAsWords() {
        XCTAssertEqual(DisplaySpeech.spokenKey("5", localize: localize), "5")
        XCTAssertEqual(DisplaySpeech.spokenKey("+", localize: localize), "plus")
        XCTAssertEqual(DisplaySpeech.spokenKey("*", localize: localize), "times")
        XCTAssertEqual(DisplaySpeech.spokenKey("÷", localize: localize), "divided by")
        XCTAssertEqual(DisplaySpeech.spokenKey("-", localize: localize), "minus")
        XCTAssertEqual(DisplaySpeech.spokenKey(".", localize: localize), "point")
        XCTAssertEqual(DisplaySpeech.spokenKey("( )", localize: localize), "parentheses")
        XCTAssertEqual(DisplaySpeech.spokenKey("C", localize: localize), "Clear entry")
    }

    // Enter and AC are covered by the result and "Cleared" announcements, and
    // keys with no meaning on the calculator say nothing.
    func testEnterAllClearAndOtherKeysAreNotSpoken() {
        XCTAssertNil(DisplaySpeech.spokenKey("=", localize: localize))
        XCTAssertNil(DisplaySpeech.spokenKey("AC", localize: localize))
        XCTAssertNil(DisplaySpeech.spokenKey("q", localize: localize))
        XCTAssertNil(DisplaySpeech.spokenKey("", localize: localize))
    }

    // The model says when a result was rounded to fit, and a typed number
    // never counts as rounded.
    func testTheModelKnowsWhenAResultWasRounded() {
        let viewModel = CalculatorViewModel()
        viewModel.inputDigit("2")
        viewModel.inputDigit("8")
        viewModel.setOperator(.divide)
        viewModel.inputDigit("3")
        viewModel.evaluate()
        XCTAssertTrue(viewModel.isDisplayRoundedResult)
        XCTAssertTrue(DisplaySpeech.spokenDisplay(viewModel.displaySpeechState, localize: localize).hasSuffix("3 3 3 repeating"))

        // Typing the very digits of a rounded result is still exact.
        for clearing in [false, true] {
            viewModel.clearAll()
            for key in ["2", "8", "÷", "3", "="] { press(key, on: viewModel) }
            if clearing { viewModel.clearAll() }
            for digit in "9.333333333333333" { press(String(digit), on: viewModel) }
            XCTAssertFalse(viewModel.isDisplayRoundedResult)
        }

        viewModel.clearAll()
        for digit in "1.222222222222222" {
            if digit == "." { viewModel.inputDecimal() } else { viewModel.inputDigit(String(digit)) }
        }
        XCTAssertFalse(viewModel.isDisplayRoundedResult)

        viewModel.clearAll()
        viewModel.inputDigit("6")
        viewModel.setOperator(.divide)
        viewModel.inputDigit("4")
        viewModel.evaluate()
        XCTAssertFalse(viewModel.isDisplayRoundedResult, "1.5 is exact")
    }

    private func press(_ key: String, on viewModel: CalculatorViewModel) {
        switch key {
        case ".": viewModel.inputDecimal()
        case "÷": viewModel.setOperator(.divide)
        case "+": viewModel.setOperator(.add)
        case "=": viewModel.evaluate()
        default: viewModel.inputDigit(key)
        }
    }

    // The on-screen AC goes through clearEntry, and is announced too.
    func testTheOnScreenACIsAnnounced() {
        let viewModel = CalculatorViewModel()
        for key in ["5", "+", "7", "="] { press(key, on: viewModel) }
        let before = viewModel.displaySpeechState
        viewModel.clearEntry()
        XCTAssertEqual(DisplaySpeech.announcement(from: before, to: viewModel.displaySpeechState, localize: localize), .cleared)
    }

    // Enter on a lone number announces it, though nothing goes to history.
    func testEnterOnALoneNumberIsAnnounced() {
        let viewModel = CalculatorViewModel()
        for key in ["4", "2"] { press(key, on: viewModel) }
        let before = viewModel.displaySpeechState
        viewModel.evaluate()
        XCTAssertEqual(
            DisplaySpeech.announcement(from: before, to: viewModel.displaySpeechState, localize: localize),
            .result("42")
        )
    }

    func testTheViewModelStateFollowsTheDisplay() {
        let viewModel = CalculatorViewModel()
        viewModel.inputDigit("5")
        viewModel.setOperator(.add)
        viewModel.inputDigit("7")
        let before = viewModel.displaySpeechState
        viewModel.evaluate()
        let after = viewModel.displaySpeechState

        XCTAssertEqual(after.completedCalculations, before.completedCalculations + 1)
        guard case .result = DisplaySpeech.announcement(from: before, to: after, localize: localize) else {
            return XCTFail("Finishing 5 + 7 should announce the result")
        }
        XCTAssertTrue(DisplaySpeech.value(for: after, localize: localize).hasPrefix("12, from 5 plus 7"))
    }

    // Every language has the new keys, so no one hears a raw key.
    func testEveryLanguageHasTheSpeechStrings() throws {
        let keys = [
            DisplaySpeech.labelKey, DisplaySpeech.hintKey,
            "a11y.display.completed", "a11y.display.pending",
            "a11y.operator.plus", "a11y.operator.minus", "a11y.operator.times",
            "a11y.operator.dividedBy", "a11y.operator.equals", "a11y.operator.approximately",
            "a11y.operator.percent", "a11y.operator.squareRoot",
            "a11y.announce.result", "a11y.announce.cleared",
            "a11y.key.point", "a11y.key.delete", "a11y.key.clear",
            "a11y.key.parentheses", "a11y.key.openParenthesis", "a11y.key.closeParenthesis",
            "a11y.number.repeating", "a11y.announce.action",
            "a11y.pane.history", "a11y.pane.closed", "a11y.announce.mode",
            "a11y.selected",
            "a11y.functionKey.current", "a11y.functionKey.hint",
            "a11y.announce.screen", "a11y.announce.window",
            "a11y.resize.keypad", "a11y.resize.keypad.hint", "a11y.resize.history", "a11y.resize.history.hint",
            "a11y.currency.cent", "a11y.currency.cents", "a11y.currency.penny", "a11y.currency.pence"
        ]
        for language in ["Base", "en", "de", "es", "fr", "ja", "zh-Hans"] {
            let path = try XCTUnwrap(Bundle.module.path(forResource: language, ofType: "lproj"), language)
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
                XCTAssertNotEqual(value, key, "\(language) is missing \(key)")
            }
        }
    }
}
