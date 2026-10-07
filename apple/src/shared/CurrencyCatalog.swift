import Foundation

/// The currency symbols the app can be set to, and how a default is picked from
/// the device's region.
///
/// The calculator engine accepts a wider set of glyphs than this
/// (`supportedCurrencySymbolCharacters`), because anything typed on a hardware
/// keyboard should still be recognized. This catalog is the narrower list that
/// is *offered*: only symbols that map to a live currency, so a symbol can
/// always be traced back to a region. Bitcoin and retired currencies are
/// deliberately absent — they remain typeable, just not selectable.
public enum CurrencyCatalog {
    public struct Option: Identifiable, Hashable {
        /// The glyph shown in the calculator display.
        public let symbol: String
        /// ISO 4217 codes that use this symbol. Several currencies share one
        /// glyph — the dollar sign alone covers a dozen — so detection matches
        /// on the code and then renders the symbol.
        public let currencyCodes: [String]

        public var id: String { symbol }
    }

    /// Fallback when the region reports a currency this catalog does not carry.
    public static let fallback = Option(
        symbol: "$",
        currencyCodes: ["USD", "CAD", "AUD", "NZD", "HKD", "SGD", "MXN", "ARS", "CLP", "COP", "TWD"]
    )

    public static let all: [Option] = [
        fallback,
        Option(symbol: "€", currencyCodes: ["EUR"]),
        Option(symbol: "£", currencyCodes: ["GBP", "GIP", "FKP", "SHP", "SYP", "LBP", "EGP", "SDG", "SSP"]),
        Option(symbol: "¥", currencyCodes: ["JPY", "CNY"]),
        Option(symbol: "₹", currencyCodes: ["INR"]),
        Option(symbol: "₩", currencyCodes: ["KRW", "KPW"]),
        Option(symbol: "₽", currencyCodes: ["RUB"]),
        Option(symbol: "₴", currencyCodes: ["UAH"]),
        Option(symbol: "₪", currencyCodes: ["ILS"]),
        Option(symbol: "₺", currencyCodes: ["TRY"]),
        Option(symbol: "฿", currencyCodes: ["THB"]),
        Option(symbol: "₫", currencyCodes: ["VND"]),
        Option(symbol: "₱", currencyCodes: ["PHP"]),
        Option(symbol: "₦", currencyCodes: ["NGN"]),
        Option(symbol: "₲", currencyCodes: ["PYG"]),
        Option(symbol: "₡", currencyCodes: ["CRC"]),
        Option(symbol: "₵", currencyCodes: ["GHS"]),
        Option(symbol: "₭", currencyCodes: ["LAK"]),
        Option(symbol: "₮", currencyCodes: ["MNT"])
    ]

    public static func option(forSymbol symbol: String) -> Option? {
        all.first { $0.symbol == symbol }
    }

    /// Resolves the symbol for an ISO 4217 currency code.
    public static func option(forCurrencyCode code: String) -> Option? {
        let normalized = code.uppercased()
        return all.first { $0.currencyCodes.contains(normalized) }
    }

    /// The symbol to use when the user has not chosen one, derived from the
    /// device region: en-GB gives £, en-US gives $, de-DE gives €.
    public static func detected(from locale: Locale = .current) -> Option {
        guard let code = locale.currency?.identifier,
              let option = option(forCurrencyCode: code) else {
            return fallback
        }

        return option
    }

    /// How many decimals amounts in this currency are shown with: 2 for most,
    /// 0 for currencies without minor units such as the yen, won or dong.
    ///
    /// A symbol can stand for several currencies (¥ is both yen and yuan), so
    /// the device's own currency is used when it shares the symbol, and the
    /// symbol's first currency otherwise. A symbol not in the catalog, such as
    /// one typed on a keyboard, gets 2.
    public static func fractionDigits(forSymbol symbol: String, locale: Locale = .current) -> Int {
        guard let option = option(forSymbol: symbol) else { return 2 }
        let localCode = locale.currency?.identifier.uppercased()
        let code = option.currencyCodes.first { $0 == localCode } ?? option.currencyCodes.first
        guard let code else { return 2 }
        return fractionDigits(forCurrencyCode: code)
    }

    /// The ISO 4217 minor-unit digits for a currency code.
    public static func fractionDigits(forCurrencyCode code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.maximumFractionDigits
    }
}
