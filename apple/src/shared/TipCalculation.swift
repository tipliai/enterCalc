import Foundation

/// A bill split into tip, total and per-person share.
///
/// All three outputs are shown together (#92), so they are derived from one
/// another rather than computed separately — the total is the bill plus the
/// tip, and the share is that total divided by the party size, so the numbers
/// on screen always agree.
public struct TipBreakdown: Equatable, Sendable {
    /// The amount before the tip.
    public let bill: Decimal
    /// The tip percentage: `18` means 18%, not 0.18.
    public let rate: Decimal
    /// `bill × rate ÷ 100`.
    public let tip: Decimal
    /// `bill + tip`.
    public let total: Decimal
    /// How many ways the total is split. Always at least 1.
    public let splitCount: Int
    /// `total ÷ splitCount`. Equal to `total` when the bill is not split.
    ///
    /// This is the exact quotient, the same way the calculator shows `10 ÷ 3`
    /// as a repeating decimal rather than rounding it. That means a share
    /// multiplied back by the party size does not always return the total to
    /// the last digit — no fixed-precision division can — so anything that
    /// rounds these for display and needs the shares to sum to the total has
    /// to allocate the remainder itself.
    public let perPerson: Decimal

    /// Quick choices for the tip percentage. A custom rate is always allowed,
    /// so this is a convenience list rather than a constraint.
    public static let presetRates: [Decimal] = [10, 15, 18, 20]

    /// The default party size: one, meaning no split.
    public static let defaultSplitCount = 1

    /// Splitting a bill zero or negative ways is not a thing a user means, so
    /// the count is clamped rather than rejected — the panel always has a
    /// sensible answer to show.
    public static let splitCountRange = 1...99

    public init(bill: Decimal, rate: Decimal, splitCount: Int = TipBreakdown.defaultSplitCount) {
        let clampedSplit = min(max(splitCount, TipBreakdown.splitCountRange.lowerBound), TipBreakdown.splitCountRange.upperBound)

        self.bill = bill
        self.rate = rate
        self.splitCount = clampedSplit

        let tip = bill * rate / 100
        self.tip = tip

        let total = bill + tip
        self.total = total
        self.perPerson = clampedSplit == 1 ? total : total / Decimal(clampedSplit)
    }
}
