import Foundation

// MARK: - Region presets

/// VAT rate presets per region, read from the bundled `vat-rates.json` (#124).
///
/// The table is data, not code: changing a rate is a one-line edit to the JSON,
/// and `VATRateTableTests` validates the file. Rates are strings in the JSON so
/// they parse to exact `Decimal`s — a JSON number such as `8.1` can come back
/// from the decoder as `8.0999…`.
public enum VATRateCatalog {
    /// One region's rates. `standard` is offered first and selected by default;
    /// `reduced` are the reduced rates consumers commonly meet.
    public struct Region: Equatable, Sendable {
        public let code: String
        public let standard: Decimal
        public let reduced: [Decimal]
        public let effective: String
        public let source: String

        /// Standard rate first, then the others in the order the table lists
        /// them, so a region such as Canada can read GST 5, HST 13 / 14 / 15.
        public var presets: [Decimal] {
            [standard] + reduced.filter { $0 != standard }
        }
    }

    public struct Table: Equatable, Sendable {
        public let updated: String
        public let fallback: [Decimal]
        public let regions: [String: Region]
    }

    /// The bundled table holds real VAT rates, which never exceed 100%; a value
    /// above that is a typo, so it fails validation.
    public static let maximumTableRate: Decimal = 100

    /// Offered when the region has no entry, or the table cannot be read.
    public static let genericPresets: [Decimal] = [5, 10, 20, 25]

    /// The VAT and Tip panels always show exactly this many preset buttons.
    public static let presetCount = 3

    /// Exactly `presetCount` presets: the given ones in order, then the generic
    /// rates they do not already include. A region with fewer than three rates
    /// (Germany has 19 and 7) is topped up, and one with more keeps its first
    /// three; each button can still be changed by
    /// pressing and holding it.
    public static func filled(_ presets: [Decimal]) -> [Decimal] {
        var result: [Decimal] = []
        for rate in presets + genericPresets + [15, 7, 12, 8] where !result.contains(rate) {
            result.append(rate)
            if result.count == presetCount { break }
        }
        return result
    }

    /// The bundled table, loaded once.
    public static let bundled: Table? = {
        guard let url = Bundle.module.url(forResource: "vat-rates", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? table(from: data)
    }()

    /// The presets for a locale's region, standard rate first.
    public static func presets(for locale: Locale = .current, in table: Table? = bundled) -> [Decimal] {
        guard let table else { return genericPresets }
        if let code = locale.region?.identifier.uppercased(), let region = table.regions[code] {
            return filled(region.presets)
        }
        return filled(table.fallback)
    }

    /// The rate the VAT panel starts on: the region's standard rate.
    public static func defaultRate(for locale: Locale = .current, in table: Table? = bundled) -> Decimal {
        presets(for: locale, in: table).first ?? 20
    }

    // MARK: Parsing

    public enum TableError: Error, Equatable {
        case unreadable
        case invalidRate(region: String, value: String)
        case rateOutOfRange(region: String, rate: Decimal)
        case duplicateRegion(String)
        case invalidRegionCode(String)
    }

    private struct RawTable: Decodable {
        let schemaVersion: Int
        let updated: String
        let fallback: [String]
        let regions: [RawRegion]
    }

    private struct RawRegion: Decodable {
        let region: String
        let standard: String
        let reduced: [String]
        let effective: String
        let source: String
    }

    /// Parses and validates a table. Any invalid entry rejects the whole table,
    /// so a bad edit fails the test suite rather than shipping half a table.
    public static func table(from data: Data) throws -> Table {
        guard let raw = try? JSONDecoder().decode(RawTable.self, from: data) else {
            throw TableError.unreadable
        }

        var regions: [String: Region] = [:]
        for entry in raw.regions {
            let code = entry.region
            guard code.count == 2, code == code.uppercased(), code.allSatisfy(\.isLetter) else {
                throw TableError.invalidRegionCode(code)
            }
            guard regions[code] == nil else { throw TableError.duplicateRegion(code) }

            let standard = try rate(entry.standard, region: code)
            let reduced = try entry.reduced.map { try rate($0, region: code) }
            regions[code] = Region(
                code: code,
                standard: standard,
                reduced: reduced,
                effective: entry.effective,
                source: entry.source
            )
        }

        let fallback = try raw.fallback.map { try rate($0, region: "fallback") }
        return Table(updated: raw.updated, fallback: fallback, regions: regions)
    }

    private static func rate(_ text: String, region: String) throws -> Decimal {
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              text.allSatisfy({ $0.isNumber || $0 == "." }) else {
            throw TableError.invalidRate(region: region, value: text)
        }
        guard value >= 0, value <= VATRateCatalog.maximumTableRate else {
            throw TableError.rateOutOfRange(region: region, rate: value)
        }
        return value
    }
}

// MARK: - Typed entry

/// A rate being typed on the VAT or Tip panel's number pad (#124).
///
/// Keeps the entry valid at every keystroke, so the panel can show live results
/// while typing: never above `maximum`, at most `maximumFractionDigits`
/// decimals, and no leading zeros. The text is held with a `.` separator and
/// shown with the active number format's.
public struct RateEntry: Equatable, Sendable {
    /// No real tax or tip exceeds 100%, but nothing forbids one, so typed rates
    /// go up to 999.999 — enough for anything plausible while keeping the
    /// field to a sensible length.
    public static let maximum: Decimal = Decimal(string: "999.999")!
    public static let maximumFractionDigits = 3

    public private(set) var text: String
    /// The first key replaces the rate being edited rather than appending to
    /// it, as on a calculator display.
    private var replacesOnNextKey: Bool

    /// Starts editing `rate`, which stays shown until the first key.
    public init(editing rate: Decimal) {
        text = RateEntry.canonicalText(for: rate)
        replacesOnNextKey = true
    }

    /// The entry for text typed into a field, or `nil` when the text is not a
    /// valid rate (a letter, a second separator, a third decimal, over 100).
    /// Accepts the given decimal separator as well as `.` and `,`.
    public init?(typed raw: String, decimalSeparator: String) {
        text = ""
        replacesOnNextKey = false
        for character in raw {
            if let digit = character.wholeNumberValue, character.isASCII {
                guard appendDigit(digit) else { return nil }
            } else if String(character) == decimalSeparator || character == "." || character == "," {
                guard appendDecimalSeparator() else { return nil }
            } else {
                return nil
            }
        }
    }

    /// The rate the text represents; `nil` while nothing has been typed.
    public var value: Decimal? {
        text.isEmpty ? nil : Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Appends a digit. Returns `false`, leaving the entry unchanged, when the
    /// digit would exceed the maximum or the decimal limit.
    @discardableResult
    public mutating func appendDigit(_ digit: Int) -> Bool {
        guard (0...9).contains(digit) else { return false }
        var candidate = replacesOnNextKey ? "" : text
        if candidate == "0" { candidate = "" }
        candidate += String(digit)
        guard isAcceptable(candidate) else { return false }
        text = candidate
        replacesOnNextKey = false
        return true
    }

    @discardableResult
    public mutating func appendDecimalSeparator() -> Bool {
        var candidate = replacesOnNextKey ? "" : text
        guard !candidate.contains(".") else { return false }
        if candidate.isEmpty { candidate = "0" }
        candidate += "."
        guard isAcceptable(candidate) else { return false }
        text = candidate
        replacesOnNextKey = false
        return true
    }

    public mutating func backspace() {
        if replacesOnNextKey {
            text = ""
        } else if !text.isEmpty {
            text.removeLast()
        }
        replacesOnNextKey = false
    }

    /// The entry as shown on the panel, with the given decimal separator.
    public func displayText(decimalSeparator: String) -> String {
        text.replacingOccurrences(of: ".", with: decimalSeparator)
    }

    private func isAcceptable(_ candidate: String) -> Bool {
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 2, parts[1].count > RateEntry.maximumFractionDigits { return false }
        guard let value = Decimal(string: candidate.hasSuffix(".") ? String(candidate.dropLast()) : candidate,
                                  locale: Locale(identifier: "en_US_POSIX")) else { return false }
        if value > RateEntry.maximum { return false }
        return true
    }

    static func canonicalText(for rate: Decimal) -> String {
        var rounded = Decimal()
        var source = rate
        NSDecimalRound(&rounded, &source, maximumFractionDigits, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    /// The stepper's next rate. Whole rates step by 1; a rate with a fraction
    /// steps by 0.5, snapping onto the half-percent grid first (8.1 → 8.5 up,
    /// 8.0 down). Clamped to 0…`maximum`.
    public static func stepped(_ rate: Decimal, up: Bool) -> Decimal {
        let isWhole = rate == rounded(rate, scale: 0, mode: .down)
        let step: Decimal = isWhole ? 1 : Decimal(string: "0.5")!
        let onGrid = isWhole ? rate : rounded(rate * 2, scale: 0, mode: up ? .up : .down) / 2
        let next: Decimal
        if onGrid != rate {
            next = onGrid
        } else {
            next = up ? rate + step : rate - step
        }
        return min(max(next, 0), maximum)
    }

    private static func rounded(_ value: Decimal, scale: Int, mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var result = Decimal()
        var source = value
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }
}
