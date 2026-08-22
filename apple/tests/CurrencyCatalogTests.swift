import XCTest
@testable import EnterCalcCore

final class CurrencyCatalogTests: XCTestCase {
    // The cases named in the issue: the default symbol should follow the
    // device's region without the user configuring anything.
    func testDetectionFollowsRegionCurrency() {
        XCTAssertEqual(CurrencyCatalog.detected(from: Locale(identifier: "en_GB")).symbol, "£")
        XCTAssertEqual(CurrencyCatalog.detected(from: Locale(identifier: "en_US")).symbol, "$")
        XCTAssertEqual(CurrencyCatalog.detected(from: Locale(identifier: "de_DE")).symbol, "€")
        XCTAssertEqual(CurrencyCatalog.detected(from: Locale(identifier: "ja_JP")).symbol, "¥")
        XCTAssertEqual(CurrencyCatalog.detected(from: Locale(identifier: "hi_IN")).symbol, "₹")
    }

    // Language alone does not determine currency: English is spoken in regions
    // using different currencies, so the region has to drive the result.
    func testDetectionUsesRegionRatherThanLanguage() {
        XCTAssertEqual(CurrencyCatalog.detected(from: Locale(identifier: "en_CA")).symbol, "$")
        XCTAssertEqual(CurrencyCatalog.detected(from: Locale(identifier: "en_IE")).symbol, "€")
        XCTAssertEqual(CurrencyCatalog.detected(from: Locale(identifier: "de_CH")).symbol, "$")
    }

    // A region whose currency the catalog does not carry must still produce a
    // usable symbol rather than leaving the setting empty.
    func testUnmappedCurrencyFallsBackToDollar() {
        XCTAssertEqual(CurrencyCatalog.detected(from: Locale(identifier: "is_IS")).symbol, "$")
        XCTAssertNil(CurrencyCatalog.option(forCurrencyCode: "XYZ"))
    }

    func testCurrencyCodeLookupIsCaseInsensitive() {
        XCTAssertEqual(CurrencyCatalog.option(forCurrencyCode: "gbp")?.symbol, "£")
        XCTAssertEqual(CurrencyCatalog.option(forCurrencyCode: "GBP")?.symbol, "£")
    }

    // Symbols are the stored value and the picker's identity, so duplicates
    // would produce two indistinguishable rows and an ambiguous lookup.
    func testSymbolsAreUnique() {
        let symbols = CurrencyCatalog.all.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count)
    }

    // A code appearing under two symbols would make detection order-dependent.
    func testCurrencyCodesAreNotSharedBetweenSymbols() {
        let codes = CurrencyCatalog.all.flatMap(\.currencyCodes)
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    // Every offered symbol must be one the calculator engine actually accepts,
    // otherwise selecting it would silently fail to enter currency mode.
    func testEveryOfferedSymbolIsAcceptedByTheEngine() {
        for option in CurrencyCatalog.all {
            let viewModel = CalculatorViewModel()
            viewModel.inputCurrencySymbol(option.symbol)
            XCTAssertEqual(
                viewModel.activeCurrencySymbol,
                option.symbol,
                "engine rejected catalog symbol \(option.symbol)"
            )
        }
    }
}
