import XCTest
@testable import EnterCalcCore

/// Long-press preset edits and the rate number pad (#124).
final class RatePresetOverridesTests: XCTestCase {
    private let defaults: [Decimal] = [19, 7]

    func testUneditedPresetsAreTheDefaults() {
        XCTAssertEqual(RatePresetOverrides().applied(to: defaults), [19, 7])
    }

    func testAnEditedSlotReplacesOnlyThatPreset() {
        var overrides = RatePresetOverrides()
        overrides.set(Decimal(string: "8.1"), forSlot: 1, default: 7)
        XCTAssertEqual(overrides.applied(to: defaults), [19, Decimal(string: "8.1")!])
        XCTAssertTrue(overrides.isEdited(1))
        XCTAssertFalse(overrides.isEdited(0))
    }

    func testSettingTheDefaultOrNilRestoresIt() {
        var overrides = RatePresetOverrides(rates: [0: 21, 1: 9])
        overrides.set(nil, forSlot: 0, default: 19)
        overrides.set(7, forSlot: 1, default: 7)
        XCTAssertEqual(overrides, RatePresetOverrides())
    }

    // Saved edits survive a relaunch exactly, fractions included.
    func testSerializationRoundTrips() {
        let overrides = RatePresetOverrides(rates: [2: 12, 0: Decimal(string: "8.1")!])
        XCTAssertEqual(overrides.serialized, "0=8.1;2=12")
        XCTAssertEqual(RatePresetOverrides(serialized: overrides.serialized), overrides)
    }

    func testMalformedStoredValuesAreSkipped() {
        let parsed = RatePresetOverrides(serialized: "0=8.1;x=3;1=;2=1500;3=-1;4=12")
        XCTAssertEqual(parsed, RatePresetOverrides(rates: [0: Decimal(string: "8.1")!, 4: 12]))
        XCTAssertEqual(RatePresetOverrides(serialized: nil), RatePresetOverrides())
    }

    func testEditsBeyondTheDefaultsAreIgnored() {
        let overrides = RatePresetOverrides(rates: [5: 12])
        XCTAssertEqual(overrides.applied(to: defaults), defaults)
    }
}

@MainActor
final class RateEditorTests: XCTestCase {
    private func editor(editing value: Decimal = 20) -> (RateEditor, live: () -> [Decimal], committed: () -> Decimal?, cancelled: () -> Bool) {
        let editor = RateEditor()
        var live: [Decimal] = []
        var committed: Decimal?
        var cancelled = false
        editor.begin(.rate, value: value, onLive: { live.append($0) }, onCommit: { committed = $0 }, onCancel: { cancelled = true })
        return (editor, { live }, { committed }, { cancelled })
    }

    func testTypingReportsEachValueLiveAndDoneCommits() {
        let (editor, live, committed, _) = editor()
        editor.press(.digit(8))
        editor.press(.decimalSeparator)
        editor.press(.digit(1))
        XCTAssertEqual(live(), [8, 8, Decimal(string: "8.1")!])
        editor.press(.done)
        XCTAssertEqual(committed(), Decimal(string: "8.1"))
        XCTAssertFalse(editor.isEditing)
    }

    func testDoneWithNothingTypedKeepsTheOriginalRate() {
        let (editor, _, committed, cancelled) = editor()
        XCTAssertTrue(editor.isEditing)
        editor.press(.done)
        XCTAssertEqual(committed(), 20, "an untouched edit commits the value it started with")

        let (cleared, _, clearedCommit, clearedCancel) = self.editor()
        cleared.press(.backspace)
        cleared.press(.done)
        XCTAssertNil(clearedCommit())
        XCTAssertTrue(clearedCancel(), "an emptied entry cancels rather than committing nothing")
        XCTAssertFalse(cancelled())
    }

    func testRefusedKeysAreNotReportedLive() {
        let (editor, live, _, _) = editor()
        editor.press(.digit(1))
        editor.press(.digit(0))
        editor.press(.digit(0))
        editor.press(.digit(5))
        XCTAssertEqual(live(), [1, 10, 100], "a fourth whole digit would exceed the maximum")
    }

    func testCancelAbandonsTheEdit() {
        let (editor, _, committed, cancelled) = editor()
        editor.press(.digit(5))
        editor.press(.cancel)
        XCTAssertNil(committed())
        XCTAssertTrue(cancelled())
        XCTAssertFalse(editor.isEditing)
        editor.press(.digit(7))
        XCTAssertFalse(editor.isEditing, "keys after closing are ignored")
    }
}

/// Text typed into the rate field (#124).
@MainActor
final class RateFieldTextTests: XCTestCase {
    func testValidTextIsAcceptedInEitherSeparator() {
        XCTAssertEqual(RateEntry(typed: "8,1", decimalSeparator: ",")?.value, Decimal(string: "8.1"))
        XCTAssertEqual(RateEntry(typed: "8.1", decimalSeparator: ",")?.value, Decimal(string: "8.1"))
        XCTAssertEqual(RateEntry(typed: "", decimalSeparator: ".")?.value, nil)
        XCTAssertNotNil(RateEntry(typed: "", decimalSeparator: "."))
    }

    func testInvalidTextIsRejected() {
        for bad in ["8a", "8.1.2", "8.1255", "1000", "1000.5", "-5", "1 2"] {
            XCTAssertNil(RateEntry(typed: bad, decimalSeparator: "."), bad)
        }
    }

    func testTheEditorReportsValidTextLiveAndRefusesInvalidText() {
        let editor = RateEditor()
        var live: [Decimal] = []
        var committed: Decimal?
        editor.begin(.rate, value: 20, onLive: { live.append($0) }, onCommit: { committed = $0 }, onCancel: {})
        XCTAssertTrue(editor.setTypedText("8,1", decimalSeparator: ","))
        XCTAssertFalse(editor.setTypedText("8,1x", decimalSeparator: ","))
        XCTAssertEqual(live, [Decimal(string: "8.1")!])
        editor.press(.done)
        XCTAssertEqual(committed, Decimal(string: "8.1"))
    }

    // A field left untouched keeps the rate it was opened on.
    func testUntouchedFieldCommitsTheOriginalRate() {
        let editor = RateEditor()
        var committed: Decimal?
        editor.begin(.preset(1), value: 7, onLive: { _ in }, onCommit: { committed = $0 }, onCancel: {})
        editor.press(.done)
        XCTAssertEqual(committed, 7)
    }
}
