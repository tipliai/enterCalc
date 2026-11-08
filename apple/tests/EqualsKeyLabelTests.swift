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

// Every key the app looks up by name exists in all seven bundles. A missing
// one shows, and VoiceOver reads, the raw key: the close buttons said "close"
// in every language until 1.2.0.
final class LocalizationKeyCoverageTests: XCTestCase {
    func testEveryLookedUpKeyIsTranslated() throws {
        let apple = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = apple.appendingPathComponent("src")
        let resources = sources.appendingPathComponent("shared/Resources")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("Source tree not reachable from this test run")
        }

        let pattern = try NSRegularExpression(pattern: #"[lL]ocalized\(\s*"([A-Za-z0-9_.]+)""#)
        var keys = Set<String>()
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { keys.insert(String(text[range])) }
            }
        }
        XCTAssertGreaterThan(keys.count, 50, "The key scan found too little to be checking anything")

        let languages = ["Base", "en", "de", "es", "fr", "ja", "zh-Hans"]
        for language in languages {
            let url = resources.appendingPathComponent("\(language).lproj/Localizable.strings")
            let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "\(language) strings")
            let missing = keys.subtracting(table.keys).sorted()
            XCTAssertEqual(missing, [], "\(language).lproj is missing keys")
        }
        XCTAssertTrue(keys.contains("close"))
    }
}
