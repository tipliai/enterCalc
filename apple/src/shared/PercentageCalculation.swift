import Foundation

// MARK: - Percentage

/// A percentage applied to a base amount, keeping the percentage *amount* and
/// the final result side by side.
///
/// The calculator already evaluates `100 + 10%` to `110`; what it cannot show
/// is the `10`. Percentage mode needs both, so the breakdown carries the
/// intermediate value rather than only the answer.
public struct PercentageBreakdown: Equatable, Sendable {
    public enum Direction: Equatable, Sendable {
        case add
        case subtract

        var sign: Decimal { self == .add ? 1 : -1 }
    }

    /// The value the percentage is taken of.
    public let base: Decimal
    /// The percentage itself: `10` means 10%, not 0.1.
    public let rate: Decimal
    public let direction: Direction
    /// `base × rate ÷ 100`. It does not flip sign with `direction` — the
    /// operation's sign lives there — so this reads as "the 10 in 100 + 10%"
    /// whether the 10% is being added or taken off. It does follow the sign of
    /// `base`, since 20% of −50 really is −10.
    public let amount: Decimal
    /// `base + amount` or `base − amount`.
    public let result: Decimal

    public init(base: Decimal, rate: Decimal, direction: Direction) {
        self.base = base
        self.rate = rate
        self.direction = direction

        let amount = base * rate / 100
        self.amount = amount
        // Derived by addition rather than recomputed, so `base ± amount`
        // always equals `result` exactly.
        self.result = base + amount * direction.sign
    }
}

// MARK: - VAT

/// A price split into its net, VAT and gross parts.
///
/// Whichever direction the split is computed from, the third value is derived
/// by subtraction or addition rather than by a second multiplication, so
/// `net + vat == gross` holds exactly and the three numbers can never disagree
/// with each other.
public struct VATBreakdown: Equatable, Sendable {
    /// Price excluding VAT.
    public let net: Decimal
    /// The VAT itself.
    public let vat: Decimal
    /// Price including VAT.
    public let gross: Decimal
    /// The rate used, as a percentage: `20` means 20%.
    public let rate: Decimal

    fileprivate init(net: Decimal, vat: Decimal, gross: Decimal, rate: Decimal) {
        self.net = net
        self.vat = vat
        self.gross = gross
        self.rate = rate
    }
}

public enum VATCalculation {
    /// Rates offered as quick choices. A custom rate is always allowed, so this
    /// is a convenience list rather than a constraint.
    public static let presetRates: [Decimal] = [5, 10, 15, 20, 25]

    /// A rate of exactly −100% would make the reverse calculation divide by
    /// zero, and anything below that inverts the price. Neither is a VAT rate.
    public static func isValidRate(_ rate: Decimal) -> Bool {
        rate > -100
    }

    /// Adds VAT to a net price: `vat = net × rate ÷ 100`, `gross = net + vat`.
    public static func adding(rate: Decimal, toNet net: Decimal) -> VATBreakdown? {
        guard isValidRate(rate) else { return nil }

        let vat = net * rate / 100
        return VATBreakdown(net: net, vat: vat, gross: net + vat, rate: rate)
    }

    /// Backs VAT out of a gross price — the reverse-VAT case.
    ///
    /// `net = gross ÷ (1 + rate ÷ 100)`, and the VAT is then the remainder
    /// rather than a second multiplication, so the parts always add back up to
    /// the price that was entered.
    public static func removing(rate: Decimal, fromGross gross: Decimal) -> VATBreakdown? {
        guard isValidRate(rate) else { return nil }

        let divisor = 1 + rate / 100
        guard divisor != 0 else { return nil }

        let net = gross / divisor
        return VATBreakdown(net: net, vat: gross - net, gross: gross, rate: rate)
    }
}
