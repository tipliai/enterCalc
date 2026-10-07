import XCTest
@testable import EnterCalcCore

/// The bundled VAT rate table and region presets (#124).
final class VATRateTableTests: XCTestCase {
    private func table(_ json: String) throws -> VATRateCatalog.Table {
        try VATRateCatalog.table(from: Data(json.utf8))
    }

    private let sample = """
    { "schemaVersion": 1, "updated": "2026-10-06", "fallback": ["5", "10", "20"],
      "regions": [
        { "region": "DE", "standard": "19", "reduced": ["7"], "effective": "2021-01-01", "source": "https://example.test/de" },
        { "region": "CH", "standard": "8.1", "reduced": ["3.8", "2.6"], "effective": "2024-01-01", "source": "https://example.test/ch" }
      ] }
    """

    // The shipped file must always parse and pass validation; a bad edit to the
    // JSON fails here rather than silently falling back in the app.
    func testBundledTableLoadsAndIsValid() throws {
        let bundled = try XCTUnwrap(VATRateCatalog.bundled, "vat-rates.json missing or invalid")
        XCTAssertFalse(bundled.regions.isEmpty)
        XCTAssertFalse(bundled.fallback.isEmpty)
        for region in bundled.regions.values {
            XCTAssertFalse(region.source.isEmpty, "\(region.code) has no source")
            XCTAssertFalse(region.effective.isEmpty, "\(region.code) has no effective date")
            XCTAssertLessThanOrEqual(region.reduced.count, 3, "\(region.code) lists too many reduced rates for the preset row")
        }
    }

    func testRatesParseToExactDecimals() throws {
        let parsed = try table(sample)
        XCTAssertEqual(parsed.regions["CH"]?.standard, Decimal(string: "8.1"))
        XCTAssertEqual(parsed.regions["CH"]?.reduced, [Decimal(string: "3.8")!, Decimal(string: "2.6")!])
    }

    func testPresetsPutTheStandardRateFirstThenOthersInListedOrder() throws {
        let parsed = try table(sample)
        XCTAssertEqual(VATRateCatalog.presets(for: Locale(identifier: "de_DE"), in: parsed), [19, 7, 5], "topped up to three")
        XCTAssertEqual(
            VATRateCatalog.presets(for: Locale(identifier: "fr_CH"), in: parsed),
            [Decimal(string: "8.1")!, Decimal(string: "3.8")!, Decimal(string: "2.6")!]
        )
        XCTAssertEqual(VATRateCatalog.defaultRate(for: Locale(identifier: "de_DE"), in: parsed), 19)
    }

    func testRegionWithoutAnEntryGetsTheFallback() throws {
        let parsed = try table(sample)
        XCTAssertEqual(VATRateCatalog.presets(for: Locale(identifier: "en_US"), in: parsed), [5, 10, 20])
        XCTAssertEqual(VATRateCatalog.presets(for: Locale(identifier: "en"), in: parsed), [5, 10, 20])
    }

    // Spot checks against docs/vat-rates-research.md, including rates that
    // changed recently and are easy to get wrong from memory.
    func testBundledTableCarriesTheVerifiedRates() throws {
        let bundled = try XCTUnwrap(VATRateCatalog.bundled)
        func presets(_ region: String) -> [Decimal] { bundled.regions[region]?.presets ?? [] }
        XCTAssertEqual(presets("DE"), [19, 7])
        XCTAssertEqual(presets("GB"), [20, 5])
        XCTAssertEqual(presets("CH").first, Decimal(string: "8.1"))
        XCTAssertEqual(presets("FI").first, Decimal(string: "25.5"))
        XCTAssertEqual(presets("RU").first, 22)
        XCTAssertEqual(presets("IN"), [18, 5, 40])
        XCTAssertEqual(presets("CA"), [5, 13, 14, 15])
        XCTAssertNil(bundled.regions["US"], "no national VAT: the US uses the fallback")
    }

    // Both panels always show three presets, whatever the region lists.
    func testEveryRegionGetsExactlyThreeDistinctPresetsStandardFirst() throws {
        let bundled = try XCTUnwrap(VATRateCatalog.bundled)
        for (code, region) in bundled.regions {
            let presets = VATRateCatalog.presets(for: Locale(identifier: "en_\(code)"), in: bundled)
            XCTAssertEqual(presets.count, 3, code)
            XCTAssertEqual(Set(presets).count, 3, "\(code) repeats a preset")
            XCTAssertEqual(presets.first, region.standard, code)
        }
        XCTAssertEqual(VATRateCatalog.presets(for: Locale(identifier: "en_US"), in: bundled).count, 3)
        XCTAssertEqual(TipBreakdown.presetRates.count, VATRateCatalog.presetCount)
    }

    func testMissingTableFallsBackToGenericPresets() {
        XCTAssertEqual(VATRateCatalog.presets(for: Locale(identifier: "de_DE"), in: nil), [5, 10, 20], "three presets even without the table")
    }

    func testInvalidEntriesRejectTheWholeTable() {
        let duplicate = sample.replacingOccurrences(of: "\"CH\"", with: "\"DE\"")
        XCTAssertThrowsError(try table(duplicate)) { XCTAssertEqual($0 as? VATRateCatalog.TableError, .duplicateRegion("DE")) }

        let outOfRange = sample.replacingOccurrences(of: "\"19\"", with: "\"119\"")
        XCTAssertThrowsError(try table(outOfRange))

        let notANumber = sample.replacingOccurrences(of: "\"7\"", with: "\"seven\"")
        XCTAssertThrowsError(try table(notANumber))

        let badCode = sample.replacingOccurrences(of: "\"DE\"", with: "\"deu\"")
        XCTAssertThrowsError(try table(badCode))

        XCTAssertThrowsError(try table("{ not json"))
    }
}

/// Typing a rate on the VAT panel's number pad (#124).
final class RateEntryTests: XCTestCase {
    private func typed(_ keys: String, from rate: Decimal = 20) -> RateEntry {
        var entry = RateEntry(editing: rate)
        for key in keys {
            switch key {
            case ".": entry.appendDecimalSeparator()
            case "<": entry.backspace()
            default: entry.appendDigit(Int(String(key))!)
            }
        }
        return entry
    }

    func testFirstKeyReplacesTheRateBeingEdited() {
        XCTAssertEqual(typed("").value, 20)
        XCTAssertEqual(typed("1").value, 1)
        XCTAssertEqual(typed("19").value, 19)
    }

    func testFractionalRatesCanBeEntered() {
        XCTAssertEqual(typed("8.1").value, Decimal(string: "8.1"))
        XCTAssertEqual(typed("5.5").value, Decimal(string: "5.5"))
        XCTAssertEqual(typed("13.5").value, Decimal(string: "13.5"))
        XCTAssertEqual(typed("25.5").value, Decimal(string: "25.5"))
        XCTAssertEqual(typed(".5").text, "0.5")
    }

    func testEntryNeverExceedsTheMaximumOrTheDecimalLimit() {
        XCTAssertEqual(typed("100").value, 100)
        XCTAssertEqual(typed("150").value, 150, "rates above 100% are allowed")
        XCTAssertEqual(typed("999.999").value, Decimal(string: "999.999"))
        XCTAssertEqual(typed("1000").text, "100", "1000% or more is refused")
        XCTAssertEqual(typed("9.975").value, Decimal(string: "9.975"), "three decimals, as in Quebec's QST")
        XCTAssertEqual(typed("8.12555").value, Decimal(string: "8.12555"), "any number of decimals is kept for the maths")
        XCTAssertEqual(typed("8..1").text, "8.1", "one separator only")
    }

    func testLeadingZeroIsReplaced() {
        XCTAssertEqual(typed("07").text, "7")
        XCTAssertEqual(typed("0.7").text, "0.7")
    }

    func testBackspace() {
        XCTAssertEqual(typed("19<").text, "1")
        XCTAssertNil(typed("<").value, "backspace first clears the rate being edited")
        XCTAssertEqual(typed("8.1<").text, "8.")
    }

    func testDisplayUsesTheGivenDecimalSeparator() {
        XCTAssertEqual(typed("8.1").displayText(decimalSeparator: ","), "8,1")
    }

    func testStepperUsesWholeStepsForWholeRatesAndHalvesOtherwise() {
        XCTAssertEqual(RateEntry.stepped(19, up: true), 20)
        XCTAssertEqual(RateEntry.stepped(19, up: false), 18)
        XCTAssertEqual(RateEntry.stepped(Decimal(string: "8.1")!, up: true), Decimal(string: "8.5"))
        XCTAssertEqual(RateEntry.stepped(Decimal(string: "8.1")!, up: false), 8)
        XCTAssertEqual(RateEntry.stepped(Decimal(string: "8.5")!, up: true), 9)
        XCTAssertEqual(RateEntry.stepped(Decimal(string: "8.5")!, up: false), 8)
        XCTAssertEqual(RateEntry.stepped(0, up: false), 0)
        XCTAssertEqual(RateEntry.stepped(100, up: true), 101)
        XCTAssertEqual(RateEntry.stepped(RateEntry.maximum, up: true), RateEntry.maximum)
    }
}
