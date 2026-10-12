import XCTest
@testable import EnterCalcCore

final class EqualsKeyLabelTests: XCTestCase {
    func testEnglishUsesTheEnterWord() {
        XCTAssertTrue(
            EqualsKeyLabel.usesEnterWord(resolvedLocalizationCode: "en")
        )
    }

    func testOtherLanguagesUseTheSymbol() {
        for code in ["de", "es", "fr", "ja", "zh-Hans"] {
            XCTAssertFalse(
                EqualsKeyLabel.usesEnterWord(resolvedLocalizationCode: code),
                "\(code) should use the = symbol"
            )
        }
    }

    // Resolved codes can carry a region, and both separators appear in Apple
    // locale identifiers.
    func testEnglishRegionalVariantsStillUseTheEnterWord() {
        for code in ["en-GB", "en_AU", "en-US", "EN"] {
            XCTAssertTrue(
                EqualsKeyLabel.usesEnterWord(resolvedLocalizationCode: code),
                "\(code) should use the Enter word"
            )
        }
    }

    // Guards against matching on a bare prefix: these are not English.
    func testCodesMerelyBeginningWithENAreNotEnglish() {
        for code in ["eng-Latn", "enm", "eo"] {
            XCTAssertFalse(
                EqualsKeyLabel.usesEnterWord(resolvedLocalizationCode: code),
                "\(code) should not be treated as English"
            )
        }
    }

    func testEmptyCodeFallsBackToTheSymbol() {
        XCTAssertFalse(
            EqualsKeyLabel.usesEnterWord(resolvedLocalizationCode: "")
        )
    }

    // The app stores "default" meaning follow the system, so the caller must
    // resolve it first; an unresolved value must not be mistaken for English.
    func testUnresolvedDefaultSelectionUsesTheSymbol() {
        XCTAssertFalse(
            EqualsKeyLabel.usesEnterWord(resolvedLocalizationCode: "default")
        )
    }
}
