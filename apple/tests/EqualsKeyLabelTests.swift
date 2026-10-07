import XCTest
@testable import EnterCalcCore

final class EqualsKeyLabelTests: XCTestCase {
    func testDefaultKeypadInEnglishUsesTheEnterWord() {
        XCTAssertTrue(
            EqualsKeyLabel.usesEnterWord(usesAlternativeKeypad: false, resolvedLocalizationCode: "en")
        )
    }

    func testDefaultKeypadInOtherLanguagesUsesTheSymbol() {
        for code in ["de", "es", "fr", "ja", "zh-Hans"] {
            XCTAssertFalse(
                EqualsKeyLabel.usesEnterWord(usesAlternativeKeypad: false, resolvedLocalizationCode: code),
                "\(code) should use the = symbol"
            )
        }
    }

    // The alternative keypad was laid out around the symbol, so the word does
    // not belong there even in English.
    func testAlternativeKeypadAlwaysUsesTheSymbol() {
        XCTAssertFalse(
            EqualsKeyLabel.usesEnterWord(usesAlternativeKeypad: true, resolvedLocalizationCode: "en")
        )
        XCTAssertFalse(
            EqualsKeyLabel.usesEnterWord(usesAlternativeKeypad: true, resolvedLocalizationCode: "de")
        )
    }

    // Resolved codes can carry a region, and both separators appear in Apple
    // locale identifiers.
    func testEnglishRegionalVariantsStillUseTheEnterWord() {
        for code in ["en-GB", "en_AU", "en-US", "EN"] {
            XCTAssertTrue(
                EqualsKeyLabel.usesEnterWord(usesAlternativeKeypad: false, resolvedLocalizationCode: code),
                "\(code) should use the Enter word"
            )
        }
    }

    // Guards against matching on a bare prefix: these are not English.
    func testCodesMerelyBeginningWithENAreNotEnglish() {
        for code in ["eng-Latn", "enm", "eo"] {
            XCTAssertFalse(
                EqualsKeyLabel.usesEnterWord(usesAlternativeKeypad: false, resolvedLocalizationCode: code),
                "\(code) should not be treated as English"
            )
        }
    }

    func testEmptyCodeFallsBackToTheSymbol() {
        XCTAssertFalse(
            EqualsKeyLabel.usesEnterWord(usesAlternativeKeypad: false, resolvedLocalizationCode: "")
        )
    }

    // The app stores "default" meaning follow the system, so the caller must
    // resolve it first; an unresolved value must not be mistaken for English.
    func testUnresolvedDefaultSelectionUsesTheSymbol() {
        XCTAssertFalse(
            EqualsKeyLabel.usesEnterWord(usesAlternativeKeypad: false, resolvedLocalizationCode: "default")
        )
    }
}
