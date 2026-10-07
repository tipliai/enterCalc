import XCTest
@testable import EnterCalcCore

final class CalculatorFunctionKeyTests: XCTestCase {
    // MARK: - Defaults

    // Every slot resolves to something before the user touches anything, and
    // the shipped layout is the one the keypad has always drawn.
    func testDefaultAssignments() {
        let assignments = CalculatorFunctionKeyAssignments.default

        XCTAssertTrue(assignments.isDefault)
        XCTAssertEqual(assignments[.action1], .undo)
        XCTAssertEqual(assignments[.action2], .redo)
        XCTAssertEqual(assignments[.action3], .toggleSign)
        XCTAssertEqual(assignments[.action4], .currency)
        XCTAssertEqual(assignments[.action5], .rounding)
        XCTAssertEqual(assignments[.action6], .backspace)
        XCTAssertEqual(assignments[.parenthesesKey], .parentheses)
        XCTAssertEqual(assignments[.percentKey], .percent)
    }

    // No slot may share a default with another, or the shipped keypad would
    // draw the same function twice.
    func testDefaultsAreUnique() {
        let defaults = CalculatorFunctionSlot.allCases.map(\.defaultFunction)
        XCTAssertEqual(Set(defaults).count, defaults.count)
    }

    // The chooser has to offer every function; a case added to the enum and
    // forgotten in `chooserOrder` would be unreachable.
    func testChooserOrderCoversEveryFunction() {
        XCTAssertEqual(Set(CalculatorFunctionKey.chooserOrder), Set(CalculatorFunctionKey.allCases))
        XCTAssertEqual(CalculatorFunctionKey.chooserOrder.count, CalculatorFunctionKey.allCases.count)
    }

    // MARK: - Assignment

    // Assigning a function that is not on the keypad simply replaces the one
    // that was there.
    func testAssigningUnusedFunctionReplacesSlot() {
        var assignments = CalculatorFunctionKeyAssignments.default
        assignments.assign(.squareRoot, to: .action5)

        XCTAssertEqual(assignments[.action5], .squareRoot)
        XCTAssertFalse(assignments.isDefault)
        // Rounding was displaced and, having nowhere to go, is simply gone.
        XCTAssertNil(assignments.slot(for: .rounding))
    }

    // Picking a function that already sits elsewhere trades the two, so the
    // displaced one is never silently lost and never appears twice.
    func testAssigningOccupiedFunctionSwaps() {
        var assignments = CalculatorFunctionKeyAssignments.default
        assignments.assign(.backspace, to: .action1)

        XCTAssertEqual(assignments[.action1], .backspace)
        XCTAssertEqual(assignments[.action6], .undo)
    }

    // Swapping the large keypad keys with action-row keys works the same way;
    // slots are not grouped for the purposes of a swap.
    func testSwapAcrossActionRowAndKeypad() {
        var assignments = CalculatorFunctionKeyAssignments.default
        assignments.assign(.undo, to: .percentKey)

        XCTAssertEqual(assignments[.percentKey], .undo)
        XCTAssertEqual(assignments[.action1], .percent)
    }

    // Re-picking what is already there is a no-op rather than a self-swap.
    func testAssigningCurrentFunctionIsNoOp() {
        var assignments = CalculatorFunctionKeyAssignments.default
        assignments.assign(.undo, to: .action1)

        XCTAssertEqual(assignments, .default)
    }

    // Swapping back restores the shipped layout exactly, which is what makes
    // "only non-defaults are stored" safe.
    func testSwappingBackReturnsToDefault() {
        var assignments = CalculatorFunctionKeyAssignments.default
        assignments.assign(.backspace, to: .action1)
        assignments.assign(.undo, to: .action1)

        XCTAssertEqual(assignments, .default)
        XCTAssertTrue(assignments.isDefault)
    }

    func testResetRestoresDefaults() {
        var assignments = CalculatorFunctionKeyAssignments.default
        assignments.assign(.squareRoot, to: .action2)
        assignments.assign(.reciprocal, to: .percentKey)
        assignments.reset()

        XCTAssertEqual(assignments, .default)
    }

    // No sequence of assignments may leave the same function in two slots.
    func testNoDuplicatesAfterRepeatedAssignments() {
        var assignments = CalculatorFunctionKeyAssignments.default
        assignments.assign(.squareRoot, to: .action1)
        assignments.assign(.square, to: .action2)
        assignments.assign(.squareRoot, to: .action2)
        assignments.assign(.percent, to: .action3)

        let shown = CalculatorFunctionSlot.allCases.map { assignments[$0] }
        XCTAssertEqual(Set(shown).count, shown.count)
    }

    // MARK: - Serialization

    // A default layout stores nothing, so a later change to a default reaches
    // users who never customised that slot.
    func testDefaultSerializesToEmptyString() {
        XCTAssertEqual(CalculatorFunctionKeyAssignments.default.serialized, "")
    }

    func testRoundTrip() {
        var assignments = CalculatorFunctionKeyAssignments.default
        assignments.assign(.squareRoot, to: .action5)
        assignments.assign(.reciprocal, to: .percentKey)

        let restored = CalculatorFunctionKeyAssignments(serialized: assignments.serialized)
        XCTAssertEqual(restored, assignments)
        for slot in CalculatorFunctionSlot.allCases {
            XCTAssertEqual(restored[slot], assignments[slot], "slot \(slot.rawValue)")
        }
    }

    // The stored string has to be stable, or every load/save cycle would look
    // like a settings change.
    func testSerializationIsStable() {
        var assignments = CalculatorFunctionKeyAssignments.default
        assignments.assign(.squareRoot, to: .action5)
        assignments.assign(.reciprocal, to: .percentKey)

        XCTAssertEqual(assignments.serialized, CalculatorFunctionKeyAssignments(serialized: assignments.serialized).serialized)
    }

    func testEmptyAndNilDeserializeToDefault() {
        XCTAssertEqual(CalculatorFunctionKeyAssignments(serialized: nil), .default)
        XCTAssertEqual(CalculatorFunctionKeyAssignments(serialized: ""), .default)
    }

    // A value written by a build that knows functions or slots this one does
    // not must still load; the parts it understands survive.
    func testUnknownEntriesAreIgnored() {
        let assignments = CalculatorFunctionKeyAssignments(serialized: "action5=squareRoot;action9=undo;action2=hyperbolicSine;garbage")

        XCTAssertEqual(assignments[.action5], .squareRoot)
        XCTAssertEqual(assignments[.action2], .redo)
    }

    // A hand-edited or corrupted value that names one function twice must not
    // produce a keypad with two identical keys.
    func testDuplicateFunctionInStoredValueIsDropped() {
        let assignments = CalculatorFunctionKeyAssignments(serialized: "action1=squareRoot;action2=squareRoot")

        XCTAssertEqual(assignments[.action1], .squareRoot)
        XCTAssertNotEqual(assignments[.action2], .squareRoot)
    }

    // An override can collide with another slot's default rather than with
    // another override; the defaulted slot has to yield.
    func testOverrideCollidingWithAnotherSlotDefaultIsRepaired() {
        let assignments = CalculatorFunctionKeyAssignments(serialized: "action1=backspace")

        XCTAssertEqual(assignments[.action1], .backspace)
        XCTAssertNotEqual(assignments[.action6], .backspace)

        let shown = CalculatorFunctionSlot.allCases.map { assignments[$0] }
        XCTAssertEqual(Set(shown).count, shown.count, "stored value produced a duplicated key")
    }

    // The repair should behave like the swap the chooser would have made: the
    // colliding slot takes the function its overrider displaced, and every
    // other slot keeps its default rather than shifting along the row.
    func testRepairSwapsWithTheDisplacedDefaultInsteadOfShiftingTheRow() {
        let assignments = CalculatorFunctionKeyAssignments(serialized: "action6=undo")

        XCTAssertEqual(assignments[.action6], .undo)
        XCTAssertEqual(assignments[.action1], .backspace)
        for slot in [CalculatorFunctionSlot.action2, .action3, .action4, .action5, .parenthesesKey, .percentKey] {
            XCTAssertEqual(assignments[slot], slot.defaultFunction, "\(slot.rawValue) moved")
        }
    }

    // Every stored single or paired override, however it collides with the
    // defaults, must load with each function shown at most once.
    func testNoStoredOverrideCombinationProducesADuplicatedKey() {
        let slots = CalculatorFunctionSlot.allCases
        let functions = CalculatorFunctionKey.allCases
        var values: [String] = []
        for slot in slots {
            for function in functions {
                values.append("\(slot.rawValue)=\(function.rawValue)")
            }
        }
        for first in values {
            for second in values {
                let assignments = CalculatorFunctionKeyAssignments(serialized: "\(first);\(second)")
                let shown = slots.map { assignments[$0] }
                XCTAssertEqual(Set(shown).count, shown.count, "\(first);\(second) duplicated a key: \(shown)")
            }
        }
    }

    // MARK: - Presentation

    // Every function needs a glyph and a translated name, or it would render
    // blank or announce its raw value.
    func testEveryFunctionHasPresentationAndLabelKey() {
        for function in CalculatorFunctionKey.allCases {
            XCTAssertFalse(function.accessibilityLabelKey.isEmpty, "\(function.rawValue)")

            switch function.presentation {
            case .symbol(let name):
                XCTAssertFalse(name.isEmpty, "\(function.rawValue)")
            case .text(let glyph):
                XCTAssertFalse(glyph.isEmpty, "\(function.rawValue)")
            case .currencySymbol:
                break
            }
        }
    }

    // Raw values are the persistence format, so renaming a case silently
    // resets everyone's layout.
    func testRawValuesAreStable() {
        XCTAssertEqual(
            Set(CalculatorFunctionKey.allCases.map(\.rawValue)),
            ["undo", "redo", "toggleSign", "currency", "rounding", "backspace",
             "squareRoot", "square", "reciprocal", "parentheses", "percent"]
        )
        XCTAssertEqual(
            Set(CalculatorFunctionSlot.allCases.map(\.rawValue)),
            ["action1", "action2", "action3", "action4", "action5", "action6",
             "parenthesesKey", "percentKey"]
        )
    }

    // MARK: - Persistence

    func testPersistenceRoundTripsAssignments() throws {
        let suiteName = "CalculatorFunctionKeyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = CalculatorScreenSettingsPersistence.load(from: defaults)
        XCTAssertEqual(settings.functionKeyAssignments, .default)

        settings.functionKeyAssignments.assign(.squareRoot, to: .action5)
        CalculatorScreenSettingsPersistence.persist(settings, to: defaults)

        let reloaded = CalculatorScreenSettingsPersistence.load(from: defaults)
        XCTAssertEqual(reloaded.functionKeyAssignments[.action5], .squareRoot)
        XCTAssertEqual(reloaded.functionKeyAssignments, settings.functionKeyAssignments)
    }

    // MARK: - Localization

    // Guards the trap from #65: a key added to Base.lproj and nowhere else
    // ships as a raw identifier with no build failure. Derived from the enum,
    // so a function added later without translations fails here.
    func testFunctionKeyLocalizationExistsAcrossSupportedBundles() throws {
        let localeCodes = ["Base", "en", "de", "es", "fr", "ja", "zh-Hans"]
        let keys = CalculatorFunctionKey.allCases.map(\.accessibilityLabelKey)
            + ["functionKey.chooser.title", "functionKey.change", "functionKey.hint"]
            // The VAT and Tip panels' rate editing (#124).
            + ["currency.rate.type", "currency.rate.editPreset", "currency.rate.presetHint",
               "currency.rate.done", "currency.rate.cancel", "currency.rate.range"]
            // The VAT and Tip panels themselves (#92).
            + ["currency.vat.title", "currency.vat.add", "currency.vat.remove", "currency.vat.rate",
               "currency.vat.rate.decrease", "currency.vat.rate.increase", "currency.vat.net",
               "currency.vat.amount", "currency.vat.gross",
               "currency.tip.title", "currency.tip.rate", "currency.tip.rate.decrease",
               "currency.tip.rate.increase", "currency.tip.split", "currency.tip.split.decrease",
               "currency.tip.split.increase", "currency.tip.amount", "currency.tip.total", "currency.tip.perPerson",
               "currency.tool.use", "currency.tool.close"]

        for localeCode in localeCodes {
            let strings = try localizedStrings(named: localeCode)
            for key in keys {
                guard let value = strings[key] as? String else {
                    XCTFail("Missing \(key) in \(localeCode).lproj")
                    continue
                }
                XCTAssertFalse(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Empty \(key) in \(localeCode).lproj"
                )
                XCTAssertNotEqual(value, key, "Untranslated \(key) in \(localeCode).lproj")
            }
        }
    }

    private func localizedStrings(named localeCode: String) throws -> NSDictionary {
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
        let bundle = Bundle(path: bundleURL.path),
        let stringsURL = bundle.url(forResource: "Localizable", withExtension: "strings"),
        let strings = NSDictionary(contentsOf: stringsURL) else {
            throw XCTSkip("Missing localization bundle: \(localeCode).lproj")
        }

        return strings
    }
}
