import XCTest
@testable import EnterCalcCore

final class CalculatorModeTests: XCTestCase {
    func testModeFollowsTheCurrencySymbol() {
        let viewModel = CalculatorViewModel()
        XCTAssertEqual(CalculatorMode.current(for: viewModel), .basic)

        viewModel.inputCurrencySymbol("€")
        XCTAssertEqual(CalculatorMode.current(for: viewModel), .currency)
    }

    func testSelectingCurrencyUsesThePageSymbolAndKeepsTheValue() {
        let viewModel = CalculatorViewModel()
        viewModel.inputDigit("4")
        viewModel.inputDigit("2")

        CalculatorMode.currency.select(on: viewModel, currencySymbol: "€")

        XCTAssertEqual(viewModel.activeCurrencySymbol, "€")
        XCTAssertTrue(viewModel.display.contains("42"))
    }

    func testSelectingBasicLeavesCurrencyMode() {
        let viewModel = CalculatorViewModel()
        viewModel.inputCurrencySymbol("$")

        CalculatorMode.basic.select(on: viewModel, currencySymbol: "$")

        XCTAssertNil(viewModel.activeCurrencySymbol)
        XCTAssertEqual(CalculatorMode.current(for: viewModel), .basic)
    }

    // Choosing the mode already showing must not swap the symbol or add an
    // undo step.
    func testSelectingTheCurrentModeDoesNothing() {
        let viewModel = CalculatorViewModel()
        viewModel.inputCurrencySymbol("£")
        let couldUndo = viewModel.canUndo

        CalculatorMode.currency.select(on: viewModel, currencySymbol: "€")

        XCTAssertEqual(viewModel.activeCurrencySymbol, "£")
        XCTAssertEqual(viewModel.canUndo, couldUndo)
    }

    func testChangingModeCanBeUndone() {
        let viewModel = CalculatorViewModel()

        CalculatorMode.currency.select(on: viewModel, currencySymbol: "$")
        viewModel.undo()

        XCTAssertEqual(CalculatorMode.current(for: viewModel), .basic)
    }

    func testShortcutsNumberTheModesInOrder() {
        XCTAssertEqual(CalculatorMode.allCases.map(\.shortcutNumber), Array(1...CalculatorMode.allCases.count))
        XCTAssertEqual(CalculatorMode.basic.shortcutNumber, 1)
    }

    func testEveryModeStringIsTranslated() {
        let keys = ["calculator.mode.menu", "calculator.mode.picker.hint"] + CalculatorMode.allCases.map(\.localizationKey)
        for language in ["Base", "en", "de", "es", "fr", "ja", "zh-Hans"] {
            guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path) else {
                XCTFail("Missing \(language).lproj")
                continue
            }
            for key in keys {
                XCTAssertNotEqual(
                    bundle.localizedString(forKey: key, value: "__missing__", table: nil),
                    "__missing__",
                    "\(key) missing in \(language)"
                )
            }
        }
    }
}
